;;; aiaos-cli-sim.el --- Elisp 连续任务建模仿真预测指导层（双轨指导） -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 1.0.0
;; Keywords: tools, sim, simulation, prediction, intent, guidance, dual-guidance

;; 本模块实现「elisp 连续任务建模仿真预测指导层」——与 LLM 连续任务指导层
;; 并行的第二条指导通道（双轨指导 / dual-guidance）。
;;
;; 核心机制：
;;   * 仿真映射（simulation mapping）：把用户意图 / 任务意图 / 任务步骤意图
;;     映射为可执行的 elisp 模型（状态 + 步骤 + 转移 + 预测 + 判断）。
;;   * 快速建模（fast modeling）：aiaos-cli-sim-define-model 一行定义模型；
;;     aiaos-cli-sim-model-intent 从自然语言/结构化描述快速生成意图模型。
;;   * 快速仿真（fast simulation）：aiaos-cli-sim-run 推进仿真并产出轨迹。
;;   * 前瞻判断（lookahead judgment）：aiaos-cli-sim-lookahead 前瞻 N 步，
;;     对每步做意图/可行性/风险判断。
;;   * 架构预判（architecture prediction）：aiaos-cli-sim-predict-architecture
;;     预判任务整体架构/计划/依赖。
;;   * 结果判断（intent judgment）：aiaos-cli-sim-judge 从（仿真/执行）结果
;;     反向判断用户意图、任务意图、步骤意图。
;;   * 反向指导（reverse guidance）：aiaos-cli-sim-guide 从仿真/判断结果
;;     生成反向指导建议，拉动机用户意图、任务意图、任务步骤意图快速完善。
;;
;; 与 LLM 指导层的关系：
;;   LLM 回复同时携带两种指导模式：
;;     - LLM 连续任务指导层（自然语言任务指导，见 aiaos-llm-full-chat）
;;     - elisp 连续任务建模仿真预测指导层（本模块，经 ;;elisp-sim 协议执行）
;;   ;;elisp-sim 程序调用本模块原语，产出结构化 JSON 仿真/预测/判断结果，
;;   作为第二条指导通道回传 LLM，形成「elisp 执行拉动意图完善」的高质量驱动机制。

;;; Commentary:

;; ;;elisp-sim 协议（与 ;;elisp-exec 并存的第二条指导通道）：
;;
;;   LLM 回复中可同时输出：
;;
;;   ;;elisp-sim
;;   (aiaos-cli-sim-evaluate
;;     '(:kind user :text "用户意图文本"
;;       :model (aiaos-cli-sim-define-model
;;                'task
;;                :steps '("理解需求" "设计架构" "实现" "验证")
;;                :transition (lambda (state input) ...)
;;                :predict (lambda (state) ...)
;;                :judge (lambda (result) ...))))
;;   ;;elisp-sim-end
;;
;;   aiaos-cli 执行该仿真程序，返回结构化 JSON（模型、意图、仿真轨迹、
;;   前瞻判断、架构预判、结果判断、反向指导），作为 elisp 指导通道回传。

;;; Code:

(require 'cl-lib)
(require 'json)

;;; === 模型注册表 ===

(defvar aiaos-cli-sim-models (make-hash-table :test 'equal)
  "注册的仿真模型注册表：name -> model-plist.")

(defun aiaos-cli-sim-register-model (name model)
  "注册名为 NAME 的仿真 MODEL（plist）。"
  (puthash name model aiaos-cli-sim-models)
  name)

(defun aiaos-cli-sim-get-model (name)
  "按 NAME 获取已注册的仿真模型；未注册返回 nil。"
  (and name (gethash name aiaos-cli-sim-models)))

(defun aiaos-cli-sim-model-p (x)
  "判断 X 是否为仿真模型（含 :kind model，或含 :name 且 :steps 的已注册模型）。"
  (and (listp x)
       (or (eq (plist-get x :kind) 'model)
           (and (plist-get x :name) (plist-get x :steps)))))

(defun aiaos-cli-sim-list-models ()
  "返回所有已注册模型名列表。"
  (let ((names nil))
    (maphash (lambda (k _) (push k names)) aiaos-cli-sim-models)
    (sort names #'string<)))

;;; === 模型定义 ===

(defun aiaos-cli-sim-define-model (name &rest spec)
  "定义并注册一个仿真模型，名为 NAME。

SPEC 为 plist，可含：
  :steps       (list of step descriptors)  —— 步骤列表
               step 可为字符串（步骤名）或 plist
               (name :type step-type :predicate fn :effect fn :input fn)
  :state       (初始状态 plist，如 (:progress 0 :data nil))
  :transition  (lambda (state input) new-state)  —— 状态转移
  :predict     (lambda (state) prediction-plist) —— 前瞻预测
  :judge       (lambda (result) judgment-plist)  —— 结果判断
  :architect   (lambda (state) architecture-plist) —— 架构预判
  :describe    (lambda (state) string) —— 状态描述

返回注册后的模型 plist（并写入注册表）。"
  (let ((model (list :name name
                     :kind 'model
                     :steps (or (plist-get spec :steps) nil)
                     :state (plist-get spec :state)
                     :transition (plist-get spec :transition)
                     :predict (plist-get spec :predict)
                     :judge (plist-get spec :judge)
                     :architect (plist-get spec :architect)
                     :describe (plist-get spec :describe))))
    (aiaos-cli-sim-register-model name model)
    model))

;;; === 步骤辅助 ===

(defun aiaos-cli-sim-step-name (step)
  "取 STEP 的名称字符串（兼容字符串/plist 两种形态）。"
  (cond ((stringp step) step)
        ((and (listp step) (plist-get step :name)) (plist-get step :name))
        ((and (listp step) (car step)) (format "%s" (car step)))
        (t (format "%s" step))))

(defun aiaos-cli-sim-step-count (model)
  "返回 MODEL 的步骤总数。"
  (length (plist-get model :steps)))

(defun aiaos-cli-sim-step-at (model idx)
  "取 MODEL 第 IDX（0 基）步的描述符；越界返回 nil。"
  (nth idx (plist-get model :steps)))

;;; === 快速建模：意图 → 模型 ===

(defun aiaos-cli-sim-model-intent (kind text &optional opts)
  "把意图 KIND（user/task/step）与文本/描述 TEXT 快速建模为意图模型。

OPTS 为 plist，可含 :steps（任务步骤列表）、:goal（目标）、
:constraints（约束列表）、:assume（前提假设）。

返回 plist：
  (:kind kind :text text :goal goal :steps steps :constraints constraints
   :features features :model-name name :predicted-plan plan)"
  (let* ((goal (or (plist-get opts :goal)
                   (and (stringp text) (string-trim text))))
         (steps (or (plist-get opts :steps)
                    (and (stringp text)
                         (split-string text "\n" t))))
         (constraints (plist-get opts :constraints))
         (features (list :kind kind
                         :goal goal
                         :step-count (length steps)
                         :has-constraints (not (null constraints))
                         :text-len (length (or text ""))))
         (plan (mapcar #'aiaos-cli-sim-step-name steps)))
    (list :kind kind
          :text text
          :goal goal
          :steps steps
          :constraints constraints
          :features features
          :predicted-plan plan)))

(defun aiaos-cli-sim-build-model-from-intent (name intent-model)
  "从意图模型 INTENT-MODEL 快速构建仿真模型，命名 NAME。
意图模型的 :steps 直接作为仿真步骤。"
  (aiaos-cli-sim-define-model
   name
   :steps (plist-get intent-model :steps)
   :state (list :kind (plist-get intent-model :kind)
                :goal (plist-get intent-model :goal)
                :progress 0
                :constraints (plist-get intent-model :constraints))
   :transition (lambda (state _input)
                 (plist-put state :progress
                            (min (1+ (or (plist-get state :progress) 0))
                                 (length (plist-get intent-model :steps)))))
   :describe (lambda (state)
               (format "进度 %d/%d" (or (plist-get state :progress) 0)
                       (length (plist-get intent-model :steps))))))

;;; === 快速仿真 ===

(defun aiaos-cli-sim--default-transition (state _input)
  "默认状态转移：步骤进度 +1。"
  (let ((p (or (plist-get state :progress) 0)))
    (plist-put state :progress (1+ p))))

(defun aiaos-cli-sim-step (model state input)
  "对 MODEL 在 STATE 下推进一个 STEP（输入 INPUT），返回新状态。"
  (let ((fn (plist-get model :transition)))
    (if (functionp fn)
        (funcall fn state input)
      (aiaos-cli-sim--default-transition state input))))

(defun aiaos-cli-sim-step-desc (model idx)
  "返回 MODEL 第 IDX 步的描述文本（供轨迹/指导用）。"
  (let ((step (aiaos-cli-sim-step-at model idx)))
    (cond ((stringp step) step)
          ((and (listp step) (plist-get step :name)) (plist-get step :name))
          ((and (listp step) (car step)) (format "%s" (car step)))
          (t (format "步骤 %d" (1+ idx))))))

(defun aiaos-cli-sim-run (model &optional state inputs max-steps)
  "快速仿真：对 MODEL 从 STATE（默认 :state）沿 INPUTS 推进，产出轨迹。

返回 plist：
  (:model name :initial-state state :steps [(step,state,output)...]
   :final-state final :progress pct :ok bool)"
  (let* ((initial (or state (plist-get model :state)))
         (inputs (or inputs nil))
         (limit (or max-steps (max 1 (aiaos-cli-sim-step-count model))))
         (cur (or initial (list :progress 0)))
         (trace nil)
         (idx 0))
    (while (and (< idx limit) (<= (or (plist-get cur :progress) 0)
                                  (aiaos-cli-sim-step-count model)))
      (let* ((inp (nth idx inputs))
             (next (aiaos-cli-sim-step model cur inp))
             (step-name (aiaos-cli-sim-step-desc model idx)))
        (push (list :step (1+ idx)
                    :name step-name
                    :state next
                    :input inp)
              trace)
        (setq cur next)
        (setq idx (1+ idx))))
    (let ((total (aiaos-cli-sim-step-count model))
          (prog (or (plist-get cur :progress) 0)))
      (list :model (plist-get model :name)
            :initial-state initial
            :steps (nreverse trace)
            :final-state cur
            :progress prog
            :pct (if (> total 0) (/ (* 100.0 prog) total) 0.0)
            :ok (>= prog total)))))

;;; === 前瞻判断 ===

(defun aiaos-cli-sim-lookahead (model &optional state n)
  "前瞻判断：从 STATE 往前瞻 N 步，对每步做可行性/风险/意图判断。

返回 plist：(:model name :horizon n :from state :steps [judgment...])"
  (let* ((initial (or state (plist-get model :state) (list :progress 0)))
         (horizon (or n 3))
         (cur initial)
         (judgments nil)
         (idx (or (plist-get cur :progress) 0)))
    (dotimes (k horizon)
      (let* ((step-desc (aiaos-cli-sim-step-desc model (+ idx k)))
             (next (aiaos-cli-sim-step model cur nil))
             (risk (aiaos-cli-sim--risk-of-step step-desc))
             (judge (aiaos-cli-sim--judge-step step-desc next risk)))
        (push (list :horizon (1+ k)
                    :step (format "%d:%s" (+ idx k 1) step-desc)
                    :risk risk
                    :judgment judge
                    :state-after next)
              judgments)
        (setq cur next)))
    (list :model (plist-get model :name)
          :horizon horizon
          :from initial
          :steps (nreverse judgments))))

(defun aiaos-cli-sim--risk-of-step (step-desc)
  "对单个步骤做快速风险预判（关键词匹配）。
返回 plist :(level verdict reasons)。"
  (let* ((lower (downcase (or step-desc "")))
         (risk-patterns
          '(("删除\\|remove\\|delete\\|rm " high "涉及破坏性删除")
            ("写入\\|write\\|save\\|append" medium "涉及持久化写入")
            ("shell\\|command\\|bash\\|exec\\|子进程" high "涉及 shell/子进程")
            ("网络\\|http\\|url\\|fetch\\|api" medium "涉及网络访问")
            ("外部\\|依赖\\|package\\|install" medium "涉及外部依赖")
            ("重构\\|refactor\\|迁移\\|migrate" medium "涉及大范围改动")
            ("验证\\|test\\|检查\\|assert" low "验证型步骤")
            ("文档\\|注释\\|readme" low "文档型步骤")))
         (hits nil)
         (level 'low))
    (dolist (pat risk-patterns)
      (when (string-match-p (car pat) lower)
        (push (nth 2 pat) hits)
        (when (member (car pat) '("删除\\|remove\\|delete\\|rm "
                                  "shell\\|command\\|bash\\|exec\\|子进程"))
          (setq level 'high))))
    (if hits
        (list :level (if (eq level 'high) 'high 'medium)
              :verdict (format "风险=%s" level)
              :reasons (nreverse hits))
      (list :level 'low :verdict "低风险" :reasons nil))))

(defun aiaos-cli-sim--judge-step (step-desc state risk)
  "对单步（含 RISK 与推演后 STATE）做意图/可行性判断。"
  (let ((level (plist-get risk :level)))
    (list :step step-desc
          :intent (format "推进步骤: %s" step-desc)
          :feasible (not (eq level 'high))
          :verdict (cond ((eq level 'high) "高风险，需先降低风险/拆分")
                         ((eq level 'medium) "中等风险，建议谨慎/确认"
                          )
                         (t "可行，可直接推进"))
          :risk level
          :state-after state)))

;;; === 架构预判 ===

(defun aiaos-cli-sim-predict-architecture (model &optional state)
  "架构预判：根据 MODEL 的步骤与依赖关系预判任务整体架构/计划。

返回 plist：(:model name :phases phases :dependency-graph deps
 :estimated-steps n :bottlenecks bottlenecks)"
  (let* ((steps (plist-get model :steps))
         (step-names (mapcar #'aiaos-cli-sim-step-name steps))
         (phases (aiaos-cli-sim--group-phases step-names))
         (bottlenecks (aiaos-cli-sim--find-bottlenecks step-names))
         (arch-fn (plist-get model :architect)))
    (list :model (plist-get model :name)
          :phases phases
          :step-count (length step-names)
          :steps step-names
          :dependency-graph (aiaos-cli-sim--deps-graph step-names)
          :estimated-steps (length step-names)
          :bottlenecks bottlenecks
          :custom (and arch-fn (funcall arch-fn (or state (plist-get model :state)))))))

(defun aiaos-cli-sim--group-phases (step-names)
  "把步骤按语义分组为阶段（阶段 = 连续同类步骤的聚合）。
返回 (list (phase-name . (step...))...)。"
  (let ((phases nil) (cur nil) (cur-key nil))
    (dolist (s step-names)
      (let* ((lower (downcase (or s "")))
             (key (cond ((string-match-p "理解\\|分析\\|需求\\|收集" lower) :analysis)
                        ((string-match-p "设计\\|架构\\|规划\\|方案" lower) :design)
                        ((string-match-p "实现\\|开发\\|编码\\|编写\\|write" lower) :implement)
                        ((string-match-p "验证\\|测试\\|检查\\|debug\\|调试" lower) :verify)
                        (t :generic))))
        (if (eq key cur-key)
            (setq cur (append cur (list s)))
          (when cur (push (cons cur-key cur) phases))
          (setq cur-key key)
          (setq cur (list s)))))
    (when cur (push (cons cur-key cur) phases))
    (nreverse phases)))

(defun aiaos-cli-sim--find-bottlenecks (step-names)
  "预判瓶颈步骤（高风险/依赖密集步骤）。
返回 (list of step names)。"
  (let ((bottlenecks nil))
    (dolist (s step-names)
      (let ((risk (aiaos-cli-sim--risk-of-step s)))
        (when (memq (plist-get risk :level) '(high medium))
          (push s bottlenecks))))
    (nreverse bottlenecks)))

(defun aiaos-cli-sim--deps-graph (step-names)
  "预判步骤间依赖关系（简单线性 + 风险标记）。
返回 (list (step . (deps...)))。"
  (let ((deps nil) (prev nil))
    (dolist (s step-names)
      (let ((risk (aiaos-cli-sim--risk-of-step s)))
        (push (cons s (if (eq (plist-get risk :level) 'high)
                          (list (or prev "前置"))
                        (and prev (list prev))))
              deps)
        (setq prev s)))
    (nreverse deps)))

;;; === 结果判断 ===

(defun aiaos-cli-sim-judge (model result)
  "从仿真/执行 RESULT 反向判断用户意图、任务意图、步骤意图。

RESULT 为执行结果（plist/字符串/数值）。返回 plist：
  (:verdict verdict :intent-kind kind :intent text :confidence conf
   :suggestions (list of 建议))"
  (let* ((judge-fn (plist-get model :judge))
         (custom (and judge-fn (funcall judge-fn result)))
         (kind (plist-get model :state-kind))
         (ok (if (listp result)
                 (or (plist-get result :ok)
                     (eq (plist-get result :status) 'success)
                     (equal (plist-get result :status) "success"))
               (not (and (stringp result)
                         (string-match-p "ERROR\\|错误\\|失败" result))))))
    (or custom
        (list :verdict (if ok 'success 'fail)
              :intent-kind (or kind 'task)
              :intent (plist-get model :goal)
              :confidence (if ok 0.85 0.3)
              :suggestions
              (if ok
                  (list "任务推进正确，可继续下一步"
                        "该步骤已按预期完成，建议进入下一阶段")
                (list "结果未达预期，建议回退并拆分步骤"
                      "建议用 ;;elisp-sim 重新建模并前瞻校验"))))))

;;; === 反向指导 ===

(defun aiaos-cli-sim-guide (sim-result)
  "从仿真/判断结果 SIM-RESULT 生成反向指导建议（字符串列表）。
拉动机用户意图、任务意图、任务步骤意图快速完善。"
  (let ((guesses nil))
    (when (listp sim-result)
      ;; 意图判断
      (let ((judge (if (plist-get sim-result :judgment)
                       (plist-get sim-result :judgment)
                     (plist-get sim-result :result))))
        (when (listp judge)
          (dolist (s (plist-get judge :suggestions))
            (push (format "[意图] %s" s) guesses))))
      ;; 前瞻判断
      (let ((la (plist-get sim-result :lookahead)))
        (when (listp la)
          (dolist (st (plist-get la :steps))
            (let ((j (plist-get st :judgment)))
              (push (format "[前瞻] 步骤 %s → %s"
                            (plist-get st :step)
                            (or (and j (plist-get j :verdict))
                                (plist-get st :verdict)))
                    guesses)))))
      ;; 架构预判
      (let ((arch (plist-get sim-result :architecture)))
        (when (listp arch)
          (dolist (b (plist-get arch :bottlenecks))
            (push (format "[架构] 瓶颈步骤: %s" b) guesses)))))
    (nreverse guesses)))

;;; === 主入口：执行仿真程序并产出结构化 JSON ===

(defun aiaos-cli-sim--key-str (k)
  "把 JSON 键 K 规范化为字符串（keyword/symbol 取其名）。"
  (cond ((keywordp k) (substring (symbol-name k) 1))
        ((symbolp k) (symbol-name k))
        (t (format "%s" k))))

(defun aiaos-cli-sim--plist-p (x)
  "判断 X 是否为 plist（偶数长度且键位全为 keyword）。"
  (and (listp x)
       (not (null x))
       (cl-evenp (length x))
       (let ((ok t)
             (i 0))
         (while (and ok (< i (length x)))
           (when (and (cl-evenp i) (not (keywordp (nth i x))))
             (setq ok nil))
           (setq i (1+ i)))
         ok)))

(defun aiaos-cli-sim--plist-to-json-safe (obj)
  "把 OBJ 递归转换为 json-encode 可安全编码的形式（字符串键）。
把 plist 转为 JSON 对象（字符串键 alist），普通列表转为数组。"
  (cond ((null obj) nil)
        ((stringp obj) obj)
        ((numberp obj) obj)
        ((symbolp obj) (symbol-name obj))
        ((vectorp obj) (mapcar #'aiaos-cli-sim--plist-to-json-safe obj))
        ((hash-table-p obj)
         (let ((h (make-hash-table :test 'equal :size (hash-table-size obj))))
           (maphash (lambda (k v)
                      (puthash (aiaos-cli-sim--key-str k)
                               (aiaos-cli-sim--plist-to-json-safe v) h))
                    obj)
           h))
        ((listp obj)
         (cond
          ;; alist（cons cell 的列表）→ JSON 对象
          ((and obj (consp (car obj)))
           (mapcar (lambda (pair)
                     (cons (aiaos-cli-sim--key-str (car pair))
                           (aiaos-cli-sim--plist-to-json-safe (cdr pair))))
                   obj))
          ;; plist（keyword 键位）→ JSON 对象
          ((aiaos-cli-sim--plist-p obj)
           (let ((pairs nil))
             (while obj
               (push (cons (aiaos-cli-sim--key-str (car obj))
                           (aiaos-cli-sim--plist-to-json-safe (cadr obj)))
                     pairs)
               (setq obj (cddr obj)))
             pairs))
          ;; 普通列表 → JSON 数组
          (t (mapcar #'aiaos-cli-sim--plist-to-json-safe obj))))
        (t (format "%s" obj))))

(defun aiaos-cli-sim-evaluate (program &optional purpose)
  "执行仿真程序 PROGRAM（含意图/模型/步骤的 plist 或 form），产出结构化 JSON。

PROGRAM 可为：
  - 已求值的 plist（:kind/:text/:model/:state/:inputs...）
  - 一个 form（会 eval），其返回 plist/模型。

流程：建模 → 仿真 → 前瞻 → 架构预判 → 结果判断 → 反向指导。
返回结构化 JSON 字符串（status=success/error）。"
  (condition-case err
      (let* ((form (if (and (listp program) (eq (car program) 'quote))
                       (cadr program)
                     program))
             (spec (if (symbolp form) (aiaos-cli-sim-get-model form) form))
             (intent-model (if (and (listp spec) (plist-get spec :kind))
                               spec
                             (aiaos-cli-sim-model-intent
                              (or (and (listp spec) (plist-get spec :kind)) 'task)
                              (or (and (listp spec) (plist-get spec :text)) "")
                              (list :steps (and (listp spec) (plist-get spec :steps))
                                    :goal (and (listp spec) (plist-get spec :goal))))))
             (model (if (aiaos-cli-sim-model-p spec)
                        spec
                      (aiaos-cli-sim-build-model-from-intent
                       (or (and (listp spec) (plist-get spec :model-name)) 'sim-model)
                       intent-model)))
             (state (or (and (listp spec) (plist-get spec :state))
                        (plist-get model :state)))
             (inputs (and (listp spec) (plist-get spec :inputs)))
             (n (and (listp spec) (plist-get spec :horizon)))
             (trace (aiaos-cli-sim-run model state inputs))
             (lookahead (aiaos-cli-sim-lookahead model state (or n 3)))
             (architecture (aiaos-cli-sim-predict-architecture model state))
             (judgment (aiaos-cli-sim-judge model trace))
             (guidance (aiaos-cli-sim-guide
                        (list :judgment judgment
                              :lookahead lookahead
                              :architecture architecture)))
             (payload
              (list :status "success"
                    :mode "dual-guidance"
                    :model (plist-get model :name)
                    :intent (aiaos-cli-sim--plist-to-json-safe intent-model)
                    :simulation (aiaos-cli-sim--plist-to-json-safe trace)
                    :lookahead (aiaos-cli-sim--plist-to-json-safe lookahead)
                    :architecture (aiaos-cli-sim--plist-to-json-safe architecture)
                    :judgment (aiaos-cli-sim--plist-to-json-safe judgment)
                    :guidance (aiaos-cli-sim--plist-to-json-safe guidance)
                    :purpose (or purpose ""))))
        (json-encode payload))
    (error
     (json-encode
      (list (cons "status" "error")
            (cons "error_type" "sim_eval_error")
            (cons "message" (error-message-string err)))))))

;;; === 便捷：把仿真 JSON 转人类可读文本 ===

(defun aiaos-cli-sim-format (json-str)
  "把仿真结果 JSON-STR 转人类可读文本（供调试/展示）。"
  (condition-case nil
      (let* ((obj (json-read-from-string json-str))
             (status (cdr (assoc "status" obj))))
        (if (not (string= status "success"))
            (format "[sim 错误] %s" (cdr (assoc "message" obj)))
          (concat
           (format "[仿真] 模型=%s\n" (cdr (assoc "model" obj)))
           (let ((arch (cdr (assoc "architecture" obj))))
             (if arch
                 (format "[架构预判] 步骤=%s 瓶颈=%s\n"
                         (cdr (assoc "step_count" arch))
                         (format "%s" (cdr (assoc "bottlenecks" arch))))
               ""))
           (let ((guidance (cdr (assoc "guidance" obj))))
             (if guidance
                 (concat (mapconcat (lambda (g) (format "  - %s" g)) guidance "\n") "\n")
               "")))))
    (error json-str)))

;;; === 自动注册一个通用任务模型（开箱即用） ===

(aiaos-cli-sim-define-model
 'generic-task
 :steps '("理解需求" "设计方案" "实现" "验证" "交付")
 :state (list :kind 'task :goal nil :progress 0 :constraints nil)
 :transition (lambda (state _input)
               (plist-put state :progress
                          (min (1+ (or (plist-get state :progress) 0)) 5)))
 :describe (lambda (state)
             (format "通用任务进度 %d/5" (or (plist-get state :progress) 0))))

(provide 'aiaos-cli-sim)

;;; aiaos-cli-sim.el ends here
