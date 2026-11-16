;;; aiaos-cli-elisp.el --- Elisp 执行与调试能力（execute_elisp 标准） -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 2.0.0
;; Keywords: tools, elisp, debug, sandbox, agent

;; 本模块为 aiaos-cli 实现 execute_elisp 标准工具（Agent Function Calling 规范）：
;;   * 工具声明：execute_elisp(code, purpose, timeout_seconds)，
;;     经由标准 tools / tool_calls / tool_call_id 链路与 LLM 交互
;;   * 结构化执行结果：{status: success|error|blocked|input_required,
;;     result_type, value, error_type, message, backtrace, execution_time_ms}
;;   * 分层安全沙箱：
;;       第一层  静态策略检查（purpose + 高危符号扫描 → blocked / input_required）
;;       第二层  子进程隔离执行（emacs --batch 独立实例，非主 Emacs eval）
;;       第三层  运行时资源限制（超时、输出截断、condition-case 错误捕获）
;;   * 兼容 ;;elisp-exec 文本协议（持续交互执行循环）

;;; Commentary:

;; execute_elisp 标准交互流程：
;;   1. aiaos-cli 在请求的 tools 数组中声明 execute_elisp 工具
;;   2. LLM 返回 tool_calls: {id, function: {name: execute_elisp,
;;      arguments: "{\"code\":...,\"purpose\":...,\"timeout_seconds\":...}"}}
;;   3. aiaos-cli 解析 arguments，执行安全策略检查，在沙箱中执行 code
;;   4. 以 role:"tool"、tool_call_id 原样关联，回传结构化 JSON 结果
;;   5. LLM 根据结果继续下一步（修正重试 / 继续执行 / 给出最终答复）

;;; Code:

(require 'aiaos-cli-core)
(require 'aiaos-cli-llm)
(require 'json)

;; 捕获本文件所在目录，供 subprocess 的 -L 参数使用。
(defconst aiaos-cli-elisp-load-dir
  (or (and load-file-name (file-name-directory load-file-name))
      default-directory
      invocation-directory))

;;; === 系统提示词（告知 LLM execute_elisp 标准与安全策略） ===

(defconst aiaos-cli-elisp-system-prompt
  "## 环境与能力说明

你当前运行在 **Emacs Lisp（Elisp）** 环境中，通过 aiaos-cli 与用户交互。

### 🖥️ 环境特性

aiaos-cli 是一个 Emacs 前端工具，所有核心逻辑都运行在 Emacs Lisp 运行时中。这意味着：

- **你可以通过 elisp 程序与我（aiaos-cli）进行双向通信**：你发送的 elisp 代码不仅可以在 Emacs 中执行，还可以通过 elisp 的函数调用、变量读写等方式与 aiaos-cli 的内部状态交互。
- **双方的沟通一部分可以通过 elisp 程序来实现**：当你需要复杂的逻辑处理、数据转换、或与 Emacs 内部模块交互时，可以直接编写 elisp 程序来完成，而不是仅通过自然语言描述。
- **执行环境与 aiaos-cli 共享同一个 Emacs 会话**：你可以访问 aiaos-cli 已加载的所有函数与变量，包括工具注册、状态管理、上下文处理等模块。

### 🔧 标准工具：execute_elisp

- **execute_elisp**：在 Emacs 环境中执行你发送的 Elisp 代码，返回结构化 JSON 结果。
  - 参数 `code`（string，必填）：要执行的 Elisp 代码。
  - 参数 `purpose`（string，必填）：简要说明执行此代码的意图，用于安全审计。
  - 参数 `timeout_seconds`（integer，可选，默认 5）：执行超时时间（秒）。
  - 返回为结构化 JSON：
    - 成功：`{\"status\":\"success\",\"result_type\":\"string|number|list|...\",\"value\":\"...\",\"stdout\":\"...\",\"stderr\":\"...\",\"execution_time_ms\":N}`
    - 代码错误：`{\"status\":\"error\",\"error_type\":\"...\",\"message\":\"...\",\"backtrace\":\"...\",\"execution_time_ms\":N}`
    - 策略拦截：`{\"status\":\"blocked\",\"reason\":\"...\",\"policy_id\":\"...\"}`
    - 需用户确认：`{\"status\":\"input_required\",\"prompt\":\"...\",\"policy_id\":\"...\",\"request_state\":\"...\"}`
  - **status 判读**：`error` 表示代码本身有问题（修正后可重试）；`blocked` 表示策略禁止（不要重试）；`input_required` 表示需要用户确认。

### 🛡️ 安全策略

- 高危操作会被静态策略检查拦截，包括：删除/重命名/写入文件、shell 命令、子进程、网络访问、动态加载代码等。
- `status=blocked`：该操作被无条件禁止，请改用其他方案。
- `status=input_required`：需要用户确认。请把 prompt 原样转达给用户；**仅在用户明确同意后**，在 `purpose` 末尾追加 `[approved-by-user]` 标记并重新调用。
- 请勿尝试绕过安全策略；所有执行都会留下审计记录（purpose + 代码内容）。

### 🐛 调试能力

- **stdout/stderr 分离**：正常输出（`princ`/`prin1`）进入 stdout，调试信息（`message`）进入 stderr，两者分开返回。
- **完整回溯**：当代码出现未捕获的错误时，会返回完整的 Lisp 回溯（backtrace），包括错误类型、发生位置的函数调用栈。
- **建议**：在代码中可以使用 `(message \"调试信息: %s\" var)` 来输出调试信息，这些信息会出现在返回结果的 `[stderr]` 区块中。

### 💡 使用建议

- 当你需要验证一段 Elisp 表达式的值、测试函数行为、或调试 Elisp 代码时，直接通过 execute_elisp 工具发送代码片段。
- 当你需要与 aiaos-cli 内部模块交互（如查询当前 provider、读取配置、调用内部函数）时，优先使用 elisp 程序。
- 请优先使用 execute_elisp 来探索和验证 Elisp 行为，而不是猜测。

### 🔁 ;;elisp-exec 持续执行协议

除了通过 execute_elisp 工具调用外，你还可以在**纯文本回复**中直接输出以 `;;elisp-exec` 注释开头的 Elisp 程序：

;;elisp-exec
(+ 1 2)
;;elisp-exec-end

aiaos-cli 会自动截取该程序，走同一套 execute_elisp 安全沙箱执行，然后把执行结果（结构化 JSON，含 stdout、[stderr] 调试信息、错误与完整回溯）作为新消息回传给你。收到结果后：

1. 若任务还需要执行代码 → 请提供**下一个**以 `;;elisp-exec` 开头的 Elisp 程序（可引用上一次结果中的变量与输出）；
2. 若任务已完成 → 直接给出**不含** `;;elisp-exec` 标记的最终文字答复。

注意：
- `;;elisp-exec` 必须单独占一行（也可用 `;;elisp-exec-end` 显式结束程序）。
- 每轮回复只放一个程序；多个步骤请分多轮逐个执行。
- 执行结果会原样回传（错误时含 ERROR 与 BACKTRACE），请根据结果修正下一轮程序。
- 最终答复中不要包含 `;;elisp-exec`，否则会被当作待执行程序继续循环。

### 🚀 持续执行协议（重要）

- 收到任务后，**持续地调用工具推进任务**，不要只描述计划就停止，也不要每做一步就停下来等待用户指示。
- 每轮工具结果返回后，继续下一步，直到任务全部完成。
- 任务全部完成后，在最终答复的**末尾**追加标记：[[TASK_COMPLETE]]
- 任务未完成时**不要**输出 [[TASK_COMPLETE]]；aiaos-cli 检测到未完成会自动让你继续执行。

### 🧭 双轨指导协议（dual-guidance，重要）

用户任务由**两条并行的指导层**共同驱动，你的每条回复应尽量同时携带这两种指导模式：

1. **LLM 连续任务指导层**：回复正文本身（自然语言的任务指导、下一步建议）。
2. **elisp 连续任务建模仿真预测指导层**：回复中以 `;;elisp-sim` 开头的 Elisp 仿真/预测程序块。

#### ;;elisp-sim 仿真/预测指导块

;;elisp-sim
(aiaos-cli-sim-evaluate
  '(:kind task
    :text \"用户/任务意图描述或目标\"
    :steps (\"理解需求\" \"设计方案\" \"实现\" \"验证\")
    :horizon 3))
;;elisp-sim-end

- 该块对用户意图、任务意图、任务步骤进行 **elisp 快速建模 → 快速仿真 → 前瞻判断 → 架构预判 → 结果判断 → 反向指导**。
- 执行后返回结构化 JSON（含 `simulation` 仿真轨迹、`lookahead` 前瞻判断、`architecture` 架构预判、`judgment` 结果判断、`guidance` 反向指导建议）。
- 结果会作为 **elisp 指导通道** 回传给你；请据此：
  - 修正/细化任务意图与步骤（建模不准 → 重新给出 `;;elisp-sim`）；
  - 用前瞻判断/架构预判提前发现风险与瓶颈；
  - 需要实际执行代码时，**同一回复中**还可给出 `;;elisp-exec` 块（双轨并存）。

#### 双轨并存示例（一条回复同时带两种指导）

[正文：LLM 层任务指导文本]

;;elisp-sim
(aiaos-cli-sim-evaluate '(:kind task :text \"...\" :steps (\"...\" \"...\")))
;;elisp-sim-end

;;elisp-exec
(+ 1 2)
;;elisp-exec-end

- aiaos-cli 会先执行 `;;elisp-sim`（返回仿真/预测/判断/反向指导），再执行 `;;elisp-exec`（返回执行结果），两条通道的结果分别回传。
- 收到结果后，据仿真结果完善意图与步骤，据执行结果推进任务；需要时给出下一轮 `;;elisp-sim` / `;;elisp-exec`。
- 任务全部完成后，给出**不含** `;;elisp-sim`/`;;elisp-exec` 标记的最终答复，并在末尾追加 [[TASK_COMPLETE]]。"

  "System prompt describing the execute_elisp standard available to the LLM.")

;;; === 配置 ===

(defcustom aiaos-cli-elisp-timeout 5
  "Default timeout in seconds for execute_elisp tool calls."
  :type 'integer
  :group 'aiaos-cli)

(defcustom aiaos-cli-elisp-max-output 8192
  "Maximum number of characters captured from stdout/stderr."
  :type 'integer
  :group 'aiaos-cli)

;;; === 第一层防御：静态安全策略 ===

(defcustom aiaos-cli-elisp-blocked-symbols
  '(kill-emacs save-buffers-kill-emacs kill-emacs-and-exit)
  "无条件禁止的符号（即使获得用户确认也不放行）。"
  :type '(repeat symbol)
  :group 'aiaos-cli)

(defcustom aiaos-cli-elisp-confirm-symbols
  '(delete-file delete-directory rename-file copy-file write-region
                append-to-file dired-delete-file
                shell-command shell-command-to-string
                call-process call-process-region
                start-process start-file-process
                url-retrieve url-retrieve-synchronously
                load load-file load-library
                eval-buffer eval-region byte-compile-file)
  "需要用户确认（input_required）的高风险符号。"
  :type '(repeat symbol)
  :group 'aiaos-cli)

(defun aiaos-cli-elisp--scan-symbols (code symbols)
  "返回 CODE 中实际出现的 SYMBOLS 列表（符号名字符串）。"
  (let ((hits nil))
    (dolist (sym symbols)
      (when (and (symbolp sym)
                 (string-match-p (concat "\\_<" (regexp-quote (symbol-name sym)) "\\_>")
                                 code))
        (setq hits (append hits (list (symbol-name sym))))))
    hits))

(defun aiaos-cli-elisp-policy-check (code &optional purpose)
  "对 CODE（及可选 PURPOSE）执行静态策略检查。

返回 plist，:decision 取值为 \"allow\" / \"blocked\" /
\"input-required\"；blocked 附 :reason 与 :policy-id；
input-required 附 :prompt、:policy-id 与 :request-state。"
  (let* ((purpose (or purpose ""))
         (blocked (aiaos-cli-elisp--scan-symbols code aiaos-cli-elisp-blocked-symbols))
         (confirm (aiaos-cli-elisp--scan-symbols code aiaos-cli-elisp-confirm-symbols))
         (purpose-risky (string-match-p "删除\\|清空\\|kill\\|delete\\|remove" purpose))
         (approved (string-match-p "\\[approved-by-user\\]" purpose))
         (request-state (concat "pending_"
                                (substring (md5 (concat code "\x00" purpose)) 0 12))))
    (cond
     ;; 无条件禁止
     (blocked
      (list :decision "blocked"
            :reason (format "代码包含无条件禁止的高危符号: %s" (mapconcat #'identity blocked ", "))
            :policy-id "policy_hard_block"))
     ;; 需要用户确认（未获批准时）
     ((and (or confirm purpose-risky)
           (not approved))
      (list :decision "input-required"
            :prompt (format "代码包含高风险操作（%s），需要用户确认后才可执行。请将本提示原样转达给用户；用户明确同意后，在 purpose 末尾追加 [approved-by-user] 重新调用。"
                            (mapconcat #'identity (or confirm '("意图涉及删除/销毁类操作")) ", "))
            :policy-id "policy_confirm_required"
            :request-state request-state))
     ;; 放行
     (t (list :decision "allow")))))

;;; === 第二/三层防御：子进程隔离执行 + 超时/输出/错误捕获 ===

(defun aiaos-cli-elisp--filter-process-msgs (buf)
  "Read content from BUF, filtering out noise lines."
  (with-current-buffer buf
    (goto-char (point-min))
    (let ((result ""))
      (while (not (eobp))
        (let ((line-start (point)))
          (if (search-forward "\n" nil t)
              (let ((line (buffer-substring-no-properties line-start (point))))
                (unless (or (string-match-p "^Process aiaos-elisp" line)
                            (string-match-p "^Loading " line))
                  (setq result (concat result line))))
            (let ((line (buffer-substring-no-properties line-start (point-max))))
              (unless (or (string-match-p "^Process aiaos-elisp" line)
                          (string-match-p "^Loading " line))
                (setq result (concat result line))))
            (goto-char (point-max)))))
      result)))

(defun aiaos-cli-elisp--runner-expr (tmpfile)
  "生成子进程执行的包装代码：执行 TMPFILE 并以标记输出结果/错误/回溯。
返回 TMPFILE 中最后一个表达式的值（而非 load-file 的 t），供结构化结果使用。"
  (format "(condition-case err
    (let ((__r (with-temp-buffer
                 (insert-file-contents \"%s\")
                 (goto-char (point-min))
                 (let ((__v nil))
                   (condition-case nil
                       (while t (setq __v (eval (read (current-buffer)) t)))
                     (end-of-file nil))
                   __v))))
      (princ \"\\n__AIAOS_RESULT__\")
      (prin1 __r)
      (princ \"\\n__AIAOS_DONE__\\n\"))
  (error
    (princ (format \"\\n__AIAOS_ERROR__%%s\\n\" (error-message-string err)))
    (princ \"__AIAOS_BACKTRACE__\\n\")
    (dolist (frame (backtrace))
      (princ (format \"  %%s\\n\" frame)))
    (princ \"__AIAOS_DONE__\\n\")))" tmpfile))

(defun aiaos-cli-elisp--strip-markers (text)
  "从 TEXT 中去掉内部标记行，得到用户可见输出。"
  (string-trim
   (mapconcat #'identity
              (delq nil
                    (mapcar (lambda (l)
                              (cond
                               ((string-match-p "__AIAOS_RESULT__" l) nil)
                               ((string-match-p "__AIAOS_ERROR__" l) nil)
                               ((string-match-p "__AIAOS_BACKTRACE__" l) nil)
                               ((string-match-p "__AIAOS_DONE__" l) nil)
                               (t l)))
                            (split-string text "\n")))
              "\n")))

(defun aiaos-cli-elisp--result-type (repr)
  "根据返回值的 prin1 表示 REPR 猜测 result_type。"
  (cond
   ((or (null repr) (string= repr "nil")) "nil")
   ((string-match-p "^\".*\"$" repr) "string")
   ((string-match-p "^[-+]?[0-9]+\\(?:\\.[0-9]+\\)?$" repr) "number")
   ((string-match-p "^(" repr) "list")
   ((string-match-p "^\\[" repr) "vector")
   ((string-match-p "^:" repr) "keyword")
   (t "symbol")))

(defun aiaos-cli-elisp--truncate (s)
  (if (> (length s) aiaos-cli-elisp-max-output)
      (concat (substring s 0 aiaos-cli-elisp-max-output) "\n...[输出已截断]")
    s))

(defun aiaos-cli-elisp--run-subprocess (code timeout-seconds)
  "在 emacs --batch 子进程中执行 CODE，返回执行信息列表。

返回: (stdout-raw stderr-raw result-repr error-msg backtrace timed-out elapsed)。"
  (let* ((tmpfile (make-temp-file "aiaos-elisp-" nil ".el"))
         (stdout-buf (generate-new-buffer " *aiaos-elisp-stdout*"))
         (stderr-buf (generate-new-buffer " *aiaos-elisp-stderr*"))
         (eval-expr (aiaos-cli-elisp--runner-expr tmpfile))
         proc timed-out start-time elapsed)
    (unwind-protect
        (progn
          (with-temp-file tmpfile
            (insert code))
          (setq start-time (float-time)
                proc (make-process
                      :name "aiaos-elisp"
                      :buffer stdout-buf
                      :stderr stderr-buf
                      :command (list invocation-name
                                     "--batch"
                                     "-L" aiaos-cli-elisp-load-dir
                                     "--eval" eval-expr)
                      :connection-type 'pipe))
          (let ((deadline (+ (float-time) (max 1 (or timeout-seconds
                                                     aiaos-cli-elisp-timeout)))))
            (catch 'timeout
              (while (process-live-p proc)
                (when (> (float-time) deadline)
                  (setq timed-out t)
                  (ignore-errors (delete-process proc))
                  (throw 'timeout nil))
                (accept-process-output proc 0.2))))
          (setq elapsed (- (float-time) start-time))
          (let ((stdout-raw (aiaos-cli-elisp--filter-process-msgs stdout-buf))
                (stderr-raw (aiaos-cli-elisp--filter-process-msgs stderr-buf)))
            (list (string-trim stdout-raw)
                  (string-trim stderr-raw)
                  (when (string-match "__AIAOS_RESULT__\\([^\n]*\\)" stdout-raw)
                    (match-string 1 stdout-raw))
                  (when (string-match "__AIAOS_ERROR__\\([^\n]*\\)" stdout-raw)
                    (match-string 1 stdout-raw))
                  (when (string-match "__AIAOS_BACKTRACE__\n\\(.*\\)" stdout-raw)
                    (let ((bt (match-string 1 stdout-raw)))
                      (if (string-match "__AIAOS_DONE__" bt)
                          (substring bt 0 (match-beginning 0))
                        bt)))
                  timed-out
                  elapsed)))
      ;; 清理主进程与 :stderr 泵进程（make-process 的 :stderr 会创建
      ;; 辅助进程读取 stderr，不删除会导致 kill-buffer 询问 running process）
      (dolist (p (process-list))
        (when (or (not proc) (eq p proc)
                  (eq (process-buffer p) stdout-buf)
                  (eq (process-buffer p) stderr-buf))
          (when (process-live-p p)
            (ignore-errors (delete-process p)))
          (ignore-errors (set-process-buffer p nil))))
      (ignore-errors (delete-file tmpfile))
      (ignore-errors (kill-buffer stdout-buf))
      (ignore-errors (kill-buffer stderr-buf)))))

;;; === execute_elisp 标准入口 ===

(defun aiaos-cli-elisp-execute (code &optional purpose timeout-seconds)
  "按 execute_elisp 标准执行 CODE，返回结构化 JSON 字符串。

PURPOSE 为意图说明（安全审计用）；TIMEOUT-SECONDS 为超时秒数。
结果 JSON 的 status 为 success / error / blocked / input_required。"
  (let* ((verdict (aiaos-cli-elisp-policy-check code purpose))
         (decision (plist-get verdict :decision)))
    (cond
     ;; 策略：无条件禁止
     ((string= decision "blocked")
      (json-encode
       (list (cons "status" "blocked")
             (cons "reason" (plist-get verdict :reason))
             (cons "policy_id" (plist-get verdict :policy-id)))))
     ;; 策略：需要用户确认
     ((string= decision "input-required")
      (if (and (not noninteractive)
               (y-or-n-p (plist-get verdict :prompt)))
          (aiaos-cli-elisp--execute-sandboxed code purpose timeout-seconds)
        (json-encode
         (list (cons "status" (if noninteractive "input_required" "blocked"))
               (cons "prompt" (plist-get verdict :prompt))
               (cons "policy_id" (plist-get verdict :policy-id))
               (cons "request_state" (plist-get verdict :request-state))
               (cons "reason" (if noninteractive
                                  "等待用户确认"
                                "用户拒绝执行"))))))
     ;; 放行 → 沙箱执行
     (t (aiaos-cli-elisp--execute-sandboxed code purpose timeout-seconds)))))

(defun aiaos-cli-elisp--execute-sandboxed (code purpose timeout-seconds)
  "在沙箱中执行 CODE 并生成结构化 JSON 结果。"
  (let* ((out (aiaos-cli-elisp--run-subprocess code timeout-seconds))
         (stdout (nth 0 out))
         (stderr (nth 1 out))
         (result-repr (nth 2 out))
         (error-msg (nth 3 out))
         (backtrace (nth 4 out))
         (timed-out (nth 5 out))
         (elapsed-ms (round (* 1000 (or (nth 6 out) 0))))
         (user-out (aiaos-cli-elisp--strip-markers stdout))
         (json-obj
          (cond
           ;; 超时
           (timed-out
            (list (cons "status" "error")
                  (cons "error_type" "timeout")
                  (cons "message" (format "执行超时（>%s 秒），已终止。可拆分任务或增大 timeout_seconds 重试。"
                                          (or timeout-seconds aiaos-cli-elisp-timeout)))
                  (cons "execution_time_ms" elapsed-ms)))
           ;; 运行错误（附带回溯）
           (error-msg
            (list (cons "status" "error")
                  (cons "error_type"
                        (replace-regexp-in-string
                         "_+$" ""
                         (substring
                          (replace-regexp-in-string "[^a-z0-9]+" "_"
                                                    (downcase error-msg))
                          0 (min 40 (length
                                     (replace-regexp-in-string "[^a-z0-9]+" "_"
                                                               (downcase error-msg)))))))
                  (cons "message" error-msg)
                  (cons "backtrace" (aiaos-cli-elisp--truncate (or backtrace "")))
                  (cons "stdout" (aiaos-cli-elisp--truncate user-out))
                  (cons "execution_time_ms" elapsed-ms)))
           ;; 成功
           (t
            (list (cons "status" "success")
                  (cons "result_type" (aiaos-cli-elisp--result-type result-repr))
                  (cons "value" (aiaos-cli-elisp--truncate
                                 (if (string-empty-p user-out)
                                     (or result-repr "(无输出)")
                                   user-out)))
                  (cons "return_value" (or result-repr "nil"))
                  (cons "stdout" (aiaos-cli-elisp--truncate user-out))
                  (cons "stderr" (aiaos-cli-elisp--truncate stderr))
                  (cons "purpose" (or purpose ""))
                  (cons "execution_time_ms" elapsed-ms))))))
    (json-encode json-obj)))

(defun aiaos-cli-elisp--json-field (json-str field)
  "从 JSON 字符串 JSON-STR 中取字段 FIELD 的值（字符串化）。"
  (ignore-errors
    (let ((obj (json-read-from-string json-str)))
      (let ((v (cdr (assoc field obj))))
        (when v (format "%s" v))))))

(defun aiaos-cli-elisp-exec (code)
  "兼容旧接口：执行 CODE，返回人类可读的结果文本。"
  (let ((json-str (aiaos-cli-elisp-execute code "（旧接口调用，未声明意图）")))
    (or (aiaos-cli-elisp--json-field json-str "value")
        json-str)))

;;; === 参数提取与工具注册 ===

(defun aiaos-cli-elisp--arg (args keys)
  "从 ARGS 中按 KEYS 依次取第一个非空值。
兼容字符串键（json-read）、symbol 键与 keyword 键。"
  (when (listp args)
    (let ((found nil))
      (dolist (k keys)
        (unless found
          (setq found (or (cdr (assoc k args))
                          (cdr (assq (intern k) args))
                          (cdr (assq (intern (concat ":" k)) args))))))
      found)))

(defun aiaos-cli-elisp--tool-handler (args)
  "execute_elisp 工具处理函数：解析参数 → 策略检查 → 沙箱执行。"
  (let ((code (aiaos-cli-elisp--arg args '("code")))
        (purpose (aiaos-cli-elisp--arg args '("purpose")))
        (timeout (aiaos-cli-elisp--arg args '("timeout_seconds" "timeout"))))
    (cond
     ((or (not code) (string-empty-p (string-trim code)))
      (json-encode (list (cons "status" "error")
                         (cons "error_type" "missing_argument")
                         (cons "message" "缺少必填参数 code"))))
     ((or (not purpose) (string-empty-p (string-trim purpose)))
      (json-encode (list (cons "status" "error")
                         (cons "error_type" "missing_argument")
                         (cons "message" "缺少必填参数 purpose（请说明执行意图，用于安全审计）"))))
     (t
      (aiaos-cli-elisp-execute code purpose timeout)))))

(aiaos-llm-register-tool
 "execute_elisp"
 (lambda (args) (aiaos-cli-elisp--tool-handler args))
 "在Emacs环境中执行一段Emacs Lisp代码，并返回结构化JSON结果。仅在需要与Emacs交互、计算或操作缓冲区时使用。"
 '(("type" . "object")
   ("properties"
    . (("code" . (("type" . "string")
                  ("description" . "要执行的Emacs Lisp代码。")))
        ("purpose" . (("type" . "string")
                      ("description" . "简要说明执行此代码的意图，用于安全审计。")))
        ("timeout_seconds" . (("type" . "integer")
                              ("description" . "执行超时时间（秒），默认5秒。")))))
   ("required" . ("code" "purpose"))))

;; 向后兼容：旧工具名 elisp-exec 走同一执行管线
(aiaos-llm-register-tool
 "elisp-exec"
 (lambda (args) (aiaos-cli-elisp--tool-handler args))
 "（已更名为 execute_elisp）在Emacs环境中执行Elisp代码，返回结构化JSON结果。"
 '(("type" . "object")
   ("properties"
    . (("code" . (("type" . "string")
                  ("description" . "要执行的Emacs Lisp代码。")))
        ("purpose" . (("type" . "string")
                      ("description" . "执行意图说明，用于安全审计。")))
        ("timeout_seconds" . (("type" . "integer")
                              ("description" . "执行超时时间（秒），默认5秒。")))))
   ("required" . ("code" "purpose"))))

(provide 'aiaos-cli-elisp)

;;; aiaos-cli-elisp.el ends here

;;; === LLM provider 状态查询辅助（elisp 适配层） ===
;; LLM 通过 execute_elisp 查询当前 provider 与 fallback 链状态，
;; 用于交互消息展示与 provider 切换决策。

(defun aiaos-cli-elisp--provider-status ()
  "返回当前 LLM provider 状态（含 fallback 链、健康排序）。"
  (let ((providers (and (boundp 'aiaos-llm-providers) aiaos-llm-providers))
        (current (and (boundp 'aiaos-llm-current-provider) aiaos-llm-current-provider))
        (chain (and (boundp 'aiaos-llm-fallback-chain) aiaos-llm-fallback-chain)))
    (json-encode
     (delq nil
           (list (cons "current_provider" (or current ""))
                 (cons "provider_count" (length providers))
                 (cons "fallback_chain" (or chain (vector)))
                 (cons "providers"
                       (apply 'vector
                              (mapcar (lambda (p)
                                        (delq nil
                                              (list (cons "name" (or (cdr (assq :name p)) ""))
                                                    (cons "model" (or (cdr (assq :model p)) ""))
                                                    (cons "status" (format "%s" (or (cdr (assq :status p)) "unknown")))
                                                    (cons "tier" (format "%s" (or (cdr (assq :tier p)) ""))))))
                                      providers))))))))

(defun aiaos-cli-elisp--provider-switch (name)
  "切换到指定 provider NAME（返回结果 JSON）。"
  (if (and name (fboundp 'aiaos-llm-set-current-provider))
      (progn
        (aiaos-llm-set-current-provider name)
        (json-encode (list (cons "status" "success")
                           (cons "provider" name)
                           (cons "message" (format "已切换到 provider: %s" name)))))
    (json-encode (list (cons "status" "error")
                       (cons "message" "provider 切换失败：缺少名称或函数未定义")))))

(provide 'aiaos-cli-elisp)
