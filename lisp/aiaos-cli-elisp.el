;;; aiaos-cli-elisp.el --- Elisp 执行与调试能力 -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 1.0.0
;; Keywords: tools, elisp, debug

;; 本模块为 aiaos-cli 提供 elisp 程序执行与调试能力：
;;   * 向 LLM 告知 aiaos-cli 运行在 Emacs 环境中
;;   * 注册 elisp-exec 工具，LLM 可发送 elisp 程序，aiaos-cli 执行并反馈结果
;;   * stdout/stderr 分离捕获，错误附带回溯

;;; Code:

(require 'aiaos-cli-core)
(require 'aiaos-cli-llm)

;; 捕获本文件所在目录，供 subprocess 的 -L 参数使用。
(defconst aiaos-cli-elisp-load-dir
  (or (and load-file-name (file-name-directory load-file-name))
      default-directory
      invocation-directory))

;;; === 系统提示词（告知 LLM elisp 能力） ===

(defconst aiaos-cli-elisp-system-prompt
  "## 环境与能力说明

你当前运行在 **Emacs Lisp（Elisp）** 环境中，通过 aiaos-cli 与用户交互。

### 🖥️ 环境特性

aiaos-cli 是一个 Emacs 前端工具，所有核心逻辑都运行在 Emacs Lisp 运行时中。这意味着：

- **你可以通过 elisp 程序与我（aiaos-cli）进行双向通信**：你发送的 elisp 代码不仅可以在 Emacs 中执行，还可以通过 elisp 的函数调用、变量读写等方式与 aiaos-cli 的内部状态交互。
- **双方的沟通一部分可以通过 elisp 程序来实现**：当你需要复杂的逻辑处理、数据转换、或与 Emacs 内部模块交互时，可以直接编写 elisp 程序来完成，而不是仅通过自然语言描述。
- **执行环境与 aiaos-cli 共享同一个 Emacs 会话**：你可以访问 aiaos-cli 已加载的所有函数与变量，包括工具注册、状态管理、上下文处理等模块。

### 🔧 可用工具

除了常规的 shell / file-read / file-write / list-dir / getcwd 工具外，你还可以使用 **elisp-exec** 工具：

- **elisp-exec**: 在 Emacs 中执行你发送的 Elisp 代码片段，返回执行结果。
  - 参数 `code`（字符串，必填）：要执行的 Elisp 代码。
  - 返回值：代码的 stdout 输出（`princ`/`prin1` 等打印函数的内容）。
  - 若代码中存在未捕获的错误，返回值会包含错误类型与完整回溯（backtrace），便于你诊断和修复。
  - 调试信息（`message` 函数输出）会单独放在 `[stderr]` 区块中，与正常输出分离。

### 🐛 调试能力

- **stdout/stderr 分离**：正常输出（`princ`/`prin1`）进入 stdout，调试信息（`message`）进入 stderr，两者分开返回。
- **完整回溯**：当代码出现未捕获的错误时，会返回完整的 Lisp 回溯（backtrace），包括错误类型、发生位置的函数调用栈。
- **建议**：在 elisp-exec 中，你可以使用 `(message \"调试信息: %s\" var)` 来输出调试信息，这些信息会出现在返回结果的 `[stderr]` 区块中。

### 💡 使用建议

- 当你需要验证一段 Elisp 表达式的值、测试函数行为、或调试 Elisp 代码时，直接通过 elisp-exec 工具发送代码片段。
- 当你需要与 aiaos-cli 内部模块交互（如查询当前 provider、读取配置、调用内部函数）时，优先使用 elisp 程序。
- 请优先使用 elisp-exec 来探索和验证 Elisp 行为，而不是猜测。"

  "System prompt describing the Elisp execution capability available to the LLM.")

;;; === elisp-exec 工具实现 ===

(defcustom aiaos-cli-elisp-timeout 30
  "Timeout in seconds for elisp-exec tool calls."
  :type 'integer
  :group 'aiaos-cli)

(defcustom aiaos-cli-elisp-max-output 8192
  "Maximum number of characters captured from stdout/stderr."
  :type 'integer
  :group 'aiaos-cli)

(defun aiaos-cli-elisp--filter-process-msgs (buf)
  "Read content from BUF, filtering out 'Process ... finished' lines."
  (with-current-buffer buf
    (goto-char (point-min))
    (let ((result ""))
      (while (not (eobp))
        (let ((line-start (point)))
          (if (search-forward "\n" nil t)
              (let ((line (buffer-substring-no-properties line-start (point))))
                (unless (string-match-p "^Process aiaos-elisp" line)
                  (setq result (concat result line))))
            (let ((line (buffer-substring-no-properties line-start (point-max))))
              (unless (string-match-p "^Process aiaos-elisp" line)
                (setq result (concat result line))))
            (goto-char (point-max)))))
      result)))

(defun aiaos-cli-elisp-exec (code)
  "Execute Elisp CODE in a subprocess and return the result.

Uses `emacs --batch' to run CODE in an isolated Emacs instance, capturing
stdout and stderr separately via `make-process' with :stderr.
On error, the error message AND the full backtrace are included in the
returned string so the LLM can diagnose and fix the issue.

Returns a string: either the stdout output, or an error description with
backtrace."
  (let* ((tmpfile (make-temp-file "aiaos-elisp-" nil ".el"))
         (stdout-buf (generate-new-buffer " *aiaos-elisp-stdout*"))
         (stderr-buf (generate-new-buffer " *aiaos-elisp-stderr*"))
         (eval-expr (format "(condition-case err
    (progn (load-file \"%s\") (princ \"\"))
  (error
    (princ (format \"ERROR: %%s\\n\\n\" err))
    (princ \"BACKTRACE:\\n\")
    (dolist (frame (backtrace))
      (princ (format \"  %%s\\n\" frame)))
    (princ \"\")))" tmpfile)))
    (unwind-protect
        (progn
          (with-temp-file tmpfile
            (insert code))
          (let ((proc (make-process
                       :name "aiaos-elisp"
                       :buffer stdout-buf
                       :stderr stderr-buf
                       :command (list invocation-name
                                      "--batch"
                                      "-L" aiaos-cli-elisp-load-dir
                                      "--eval" eval-expr)
                       :connection-type 'pipe)))
            (while (process-live-p proc)
              (accept-process-output proc 0.2))
            (let ((stdout (string-trim (aiaos-cli-elisp--filter-process-msgs stdout-buf)))
                  (stderr (string-trim (aiaos-cli-elisp--filter-process-msgs stderr-buf))))
              (let ((output (if (> (length stderr) 0)
                                (concat stdout "\n\n[stderr]\n" stderr)
                              stdout)))
                (when (> (length output) aiaos-cli-elisp-max-output)
                  (setq output (concat (substring output 0 aiaos-cli-elisp-max-output)
                                       "\n...[输出已截断]")))
                (or (string-trim output) "(无输出)")))))
      (ignore-errors (delete-file tmpfile))
      (ignore-errors (kill-buffer stdout-buf))
      (ignore-errors (kill-buffer stderr-buf)))))

;;; === 注册 elisp-exec 工具 ===

(aiaos-llm-register-tool
 "elisp-exec"
 (lambda (args)
   (let ((code (or (cdr (assq :code args))
                   (cdr (assq 'code args)))))
     (if code
         (aiaos-cli-elisp-exec code)
       "Missing `code` parameter")))
 "Execute Elisp code in the Emacs environment and return the result.

The `code` parameter is a string containing the Elisp expression to evaluate.

- stdout output (from `princ`/`prin1`) is returned directly.
- Debug output (from `message`) is placed in a separate [stderr] section.
- If an unhandled error occurs, the error message and full backtrace are
  included so you can diagnose and fix the issue."
 '(("type" . "object")
   ("properties"
    . (("code" . (("type" . "string")
                  ("description" . "The Elisp code to execute.")))))
   ("required" . ("code"))))

(provide 'aiaos-cli-elisp)
