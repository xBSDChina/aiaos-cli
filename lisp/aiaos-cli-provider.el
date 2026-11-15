;;; aiaos-cli-provider.el --- AIAOS-CLI Provider 管理 -*- lexical-binding: t; -*-

;; Copyright (C) 2024 AIAOS Project
;; Author: AIAOS Team
;; Version: 1.0.0
;; Package-Requires: ((emacs "29.1") (aiaos-cli-core "1.0.0") (aiaos-cli-skill "1.0.0") (json "1.0"))
;; Keywords: tools, ai, provider

;;; Commentary:
;; Provider 管理核心模块：
;; - Provider 数据结构（name/api-key/base-url/model/tier/status）
;; - 持久化到 ~/.aiaos/providers.json
;; - CRUD 操作
;; - 分级管理（full/active/block）

;;; Code:

(require 'aiaos-cli-core)
(require 'aiaos-cli-skill)
(require 'json)
(require 'cl-lib)


;; 配置目录
(defun aiaos-cli-provider--config-dir ()
  "返回 Provider 配置目录路径。"
  (expand-file-name "aiaos" (expand-file-name ".config" (expand-file-name "~"))))


;; Provider 配置文件路径
(defvar aiaos-cli-provider--config-file
  (expand-file-name "llm_providers.json" (aiaos-cli-provider--config-dir))
  "Provider 配置文件路径。")


;; Provider 数据缓存
(defvar aiaos-cli-provider--cache nil
  "Provider 列表缓存。")


;;;###autoload
(defun aiaos-cli-provider--default-providers ()
  "返回默认 Provider 列表（不包含 API Key）。"
  '((:name "deepseek-ai/DeepSeek-V3.2" :base-url "https://api.deepseek.com/v1" :model "deepseek-chat" :tier "active")
    (:name "anthropic/claude-opus-4.5" :base-url "https://api.anthropic.com/v1" :model "claude-opus-4-5" :tier "active")
    (:name "anthropic/claude-sonnet-4.5" :base-url "https://api.anthropic.com/v1" :model "claude-sonnet-4-5" :tier "active")
    (:name "anthropic/claude-haiku-4.5" :base-url "https://api.anthropic.com/v1" :model "claude-haiku-4-5" :tier "active")
    (:name "openai/gpt-5.1" :base-url "https://api.openai.com/v1" :model "gpt-5.1" :tier "active")))


;;;###autoload
(defun aiaos-cli-provider--load-config (&optional file)
  "从 FILE (默认 aiaos-cli-provider--config-file) 加载 Provider 配置。

返回 Provider plist 列表。如果文件不存在，返回默认 Provider 列表。"
  (let ((path (or file aiaos-cli-provider--config-file)))
    (if (file-readable-p path)
        (with-no-warnings
          (condition-case err
              (let ((inhibit-read-only t)
                    (content (with-temp-buffer
                               (insert-file-contents path)
                               (buffer-string))))
                (aiaos-cli-provider--parse-config (json-read-from-string content)))
            (error
             (aiaos-cli-log-warn "Error loading provider config: %s" err)
             nil)))
      (aiaos-cli-provider--default-providers))))


;;;###autoload
(defun aiaos-cli-provider--parse-config (data)
  "解析 DATA (来自 JSON) 为 Provider plist 列表。
DATA 可能是 alist（JSON 对象解析为 alist，key 为符号）、hash-table 或 vector。"
  (let* ((providers-data data)
         (result '()))
    ;; Unwrap "providers" key if present
    (cond
     ;; alist format: ((default_provider . "sensenova") (providers ...))
     ((and (listp data) (not (hash-table-p data)))
      (let ((p (assoc-default 'providers data)))
        (when p (setq providers-data p))))
     ;; hash-table format
     ((hash-table-p data)
      (setq providers-data (gethash "providers" data)))
     ;; vector format (JSON array)
     ((vectorp data)
      (setq providers-data data)))
    ;; Normalize providers-data to a list
    (when (vectorp providers-data)
      (setq providers-data (append providers-data nil)))
    ;; Process providers-data
    (cond
     ;; providers-data is a list of provider entries
     ((and (listp providers-data) (not (hash-table-p providers-data)))
      (dolist (item providers-data)
        (let ((plist nil))
          (cond
           ;; item is hash-table -> convert to plist
           ((hash-table-p item)
            (maphash (lambda (k v)
                       (setq plist (plist-put plist (intern (format ":%s" k)) v)))
                     item))
           ;; item is vector -> convert to plist
           ((vectorp item)
            (let ((lst (append item nil)))
              (dolist (pair lst)
                (when (and (listp pair) (consp pair))
                  (let ((k (car pair))
                        (v (cdr pair)))
                    (when (symbolp k)
                      (setq plist (plist-put plist (intern (format ":%s" k)) v))))))))
           ;; item is alist: ((name . "xunfei") (api-key . "...") ...)
           ((and (listp item) (consp (car item)))
            (dolist (pair item)
              (when (and (listp pair) (consp pair))
                (let ((k (car pair))
                      (v (cdr pair)))
                  (when (symbolp k)
                    (setq plist (plist-put plist (intern (format ":%s" k)) v)))))))
           ;; Already a plist
           ((listp item)
            (setq plist item)))
          (when plist
            (push plist result)))))
     (t nil))
    (nreverse result)))

(defun aiaos-cli-provider--load ()
  "从配置文件加载所有 Provider。"
  (let ((providers (aiaos-cli-provider--load-config)))
    (setq aiaos-cli-provider--cache providers)
    (aiaos-cli-log-debug "Loaded %d providers" (length providers))
    providers))


;;;###autoload
(defun aiaos-cli-provider--save (providers)
  "将 PROVIDERS 保存到配置文件。"
  (let* ((file aiaos-cli-provider--config-file)
         (inhibit-read-only t)
         (json-encoding-pretty-print t)
         (make-backup-files nil)
         (alist (mapcar (lambda (p)
                          (let ((name (plist-get p :name))
                                (api-key (plist-get p :api-key))
                                (base-url (plist-get p :base-url))
                                (model (plist-get p :model))
                                (tier (plist-get p :tier))
                                (api (plist-get p :api)))
                            (append (list (cons "name" name))
                                    (when api-key (list (cons "api-key" api-key)))
                                    (when base-url (list (cons "base-url" base-url)))
                                    (when model (list (cons "model" model)))
                                    (when tier (list (cons "tier" tier)))
                                    (when api (list (cons "api" api))))))
                        providers))
         (content (json-encode (list (cons "providers" alist)))))
    (aiaos-cli-log-debug "Saving providers to %s" file)
    (with-temp-file file
      (insert content))
    (setq aiaos-cli-provider--cache providers)))(defun aiaos-cli-provider--list ()
  "返回所有 Provider 列表。"
  (if aiaos-cli-provider--cache
      aiaos-cli-provider--cache
    (aiaos-cli-provider--load)))


;;;###autoload
(defun aiaos-cli-provider--get (name)
  "根据名称 NAME 获取 Provider。"
  (let ((providers (aiaos-cli-provider--list)))
    (seq-find (lambda (p) (equal (plist-get p :name) name)) providers)))


;;;###autoload
(defun aiaos-cli-provider--find (name)
  "根据名称 NAME 查找 Provider。"
  (aiaos-cli-provider--get name))


;;;###autoload
(defun aiaos-cli-provider--add (&rest args)
  "添加 Provider。

接受两种形式：
- 单个 plist: (aiaos-cli-provider--add '(:name \"x\" :api-key \"y\" ...))
- 平铺参数: (aiaos-cli-provider--add name :api-key api-key :base-url url :model m :tier t)

返回 provider plist 或带 :error 的 plist。"
  (let ((provider
         (cond
          ;; Already a plist (starts with keyword or list)
          ((and args (consp (car args)))
           (if (aiaos-cli-provider--plistp (car args))
               (car args)
             (aiaos-cli-provider--build-provider-from-args args)))
          ;; Flat args starting with name (string)
          ((and args (stringp (car args)))
           (aiaos-cli-provider--build-provider-from-args args))
          ;; Single string name
          ((and args (stringp (car args)))
           (list :name (car args)))
          (t nil))))
    (if (null provider)
        (list :error "Invalid arguments to aiaos-cli-provider--add")
      (let ((name (plist-get provider :name))
            (providers (aiaos-cli-provider--list)))
        (cond
         ((not name)
          (list :error "Provider name is required"))
         ((aiaos-cli-provider--get name)
          (list :error (format "Provider %s already exists" name)))
         (t
          (push provider providers)
          (aiaos-cli-provider--save providers)
          (list :status provider)))))))


;;;###autoload

(defun aiaos-cli-provider-name (provider)
  "返回 PROVIDER 的 name 字段。"
  (plist-get provider :name))

(defun aiaos-cli-provider-tier (provider)
  "返回 PROVIDER 的 tier 字段。"
  (plist-get provider :tier))

(defun aiaos-cli-provider-model (provider)
  "返回 PROVIDER 的 model 字段。"
  (plist-get provider :model))

(defun aiaos-cli-provider-base-url (provider)
  "返回 PROVIDER 的 base-url 字段。"
  (plist-get provider :base-url))

(defun aiaos-cli-provider-status (provider)
  "返回 PROVIDER 的 status 字段。"
  (plist-get provider :status))

(defun aiaos-cli-provider--build-provider-from-args (args)
  "从平铺参数 ARGS 构建 provider plist。

ARGS 格式: name :api-key key :base-url url :model m :tier t"
  (let* ((name (car args))
         (plist (list :name name))
         (rest (cdr args)))
    (while rest
      (let ((kw (car rest))
            (val (cadr rest)))
        (when (keywordp kw)
          (setq plist (plist-put plist kw val)))
        (setq rest (cddr rest))))
    plist))


(defun aiaos-cli-provider--plistp (lst)
  "检查 LST 是否看起来像 plist（包含 keyword 元素）。"
  (and (listp lst)
       (seq-some (lambda (x) (and (keywordp x)))
                 lst)))


;;;###autoload
(defun aiaos-cli--plist-merge (base overrides)
  "Merge OVERRIDES into BASE, returning a new plist."
  (let ((result (copy-sequence base)))
    (dolist (pair overrides result)
      (when (and (consp pair) (keywordp (car pair)))
        (setq result (plist-put result (car pair) (cdr pair)))))
    result))


(defun aiaos-cli-provider--update (name updates)
  "更新名为 NAME 的 Provider，合并 UPDATES。"
  (let ((providers (aiaos-cli-provider--list))
        (provider (aiaos-cli-provider--get name)))
    (unless provider
      (error "Provider %s not found" name))
    (let ((updated (aiaos-cli--plist-merge provider updates)))
      (setq providers (cl-delete provider providers :test #'equal))
      (push updated providers)
      (aiaos-cli-provider--save providers)
      updated)))


;;;###autoload
(defun aiaos-cli-provider--delete (name)
  "删除名为 NAME 的 Provider。"
  (let ((providers (aiaos-cli-provider--list))
        (provider (aiaos-cli-provider--get name)))
    (unless provider
      (error "Provider %s not found" name))
    (setq providers (delq provider providers))
    (aiaos-cli-provider--save providers)
    t))


;;;###autoload
(defun aiaos-cli-provider--remove (&rest args)
  "删除 Provider。

接受: (aiaos-cli-provider--remove name) 或 (aiaos-cli-provider--remove)
返回 (list :status name) 或 (list :error msg)。"
  (let* ((name (if (car args) (car args) nil))
         (success (if name (aiaos-cli-provider--delete name) nil)))
    (if (not success)
        (list :error (format "Provider %s not found" name))
      (list :status name))))


;;;###autoload
(defun aiaos-cli-provider--set-tier (name tier)
  "设置 NAME 的分级为 TIER。

TIER 可以是 full/active/block。"
  (aiaos-cli-provider--update name (list :tier tier)))


;;;###autoload
(defun aiaos-cli-provider--get-tier (name)
  "获取 NAME 的分级。"
  (let ((provider (aiaos-cli-provider--get name)))
    (if provider
        (plist-get provider :tier)
      nil)))


;;;###autoload
(defun aiaos-cli-provider--tier-get (name)
  "获取 NAME 的 tier。"
  (aiaos-cli-provider--get-tier name))


;;;###autoload
(defun aiaos-cli-provider--tier-set (name tier)
  "设置 NAME 的 tier。"
  (aiaos-cli-provider--set-tier name tier))


;;;###autoload
(defun aiaos-cli-provider--set-api-key (name api-key)
  "设置 NAME 的 API Key。"
  (aiaos-cli-provider--update name (list :api-key api-key)))


;;;###autoload
(defun aiaos-cli-provider--get-api-key (name)
  "获取 NAME 的 API Key。"
  (let ((provider (aiaos-cli-provider--get name)))
    (if provider
        (plist-get provider :api-key)
      nil)))


;;;###autoload
(defun aiaos-cli-provider--select-by-model (model)
  "选择支持 MODEL 的 Provider。

返回第一个匹配的 Provider plist。"
  (let ((providers (aiaos-cli-provider--list)))
    (seq-find (lambda (p)
                (and (equal (plist-get p :model) model)
                     (not (equal (plist-get p :tier) "block"))))
              providers)))


;;;###autoload
(defun aiaos-cli-provider--import (file)
  "从 FILE 导入 Provider 配置。

FILE 格式：JSON 数组或 {\"providers\": [...]} 对象。"
  (let* ((data (with-temp-buffer
                 (insert-file-contents file)
                 (json-read-from-string (buffer-string))))
         (providers (aiaos-cli-provider--parse-config data)))
    (let ((existing (aiaos-cli-provider--list)))
      (dolist (p providers)
        (let ((existing-p (aiaos-cli-provider--get (plist-get p :name))))
          (if existing-p
              (aiaos-cli-provider--update (plist-get p :name) p)
            (push p existing))))
      (aiaos-cli-provider--save existing))
    (aiaos-cli-log-info "Imported %d providers from %s"
                               (length providers) file)))


;;;###autoload
(defun aiaos-cli-provider--export (file &optional providers)
  "将 Provider 配置导出到 FILE。

默认导出所有 Provider，或指定的 PROVIDERS。"
  (let ((providers (or providers (aiaos-cli-provider--list))))
    (with-temp-file file
      (insert (json-encode providers)))
    (aiaos-cli-log-info "Exported %d providers to %s"
                               (length providers) file)
    file))


;;;###autoload
(defun aiaos-cli-provider--to-input-params (provider)
  "将 PROVIDER 转换为 API 请求的 input-params。

返回 plist 包含 base-url, api-key, model。"
  (list :base-url (plist-get provider :base-url)
        :api-key (plist-get provider :api-key)
        :model (plist-get provider :model)))


;;;###autoload
(defun aiaos-cli-provider--audit (provider)
  "审计 PROVIDER，记录配置完整性。

返回审计记录 plist。"
  (let* ((name (plist-get provider :name))
         (api-key (plist-get provider :api-key))
         (base-url (plist-get provider :base-url))
         (model (plist-get provider :model))
         (tier (plist-get provider :tier))
         (timestamp (format-time-string "%Y-%m-%d %H:%M:%S")))
    (list :name name
          :timestamp timestamp
          :has-api-key (not (null api-key))
          :has-base-url (not (null base-url))
          :has-model (not (null model))
          :tier tier
          :status (cond ((and api-key base-url model) "ok")
                        ((not api-key) "missing-api-key")
                        ((not base-url) "missing-base-url")
                        ((not model) "missing-model")
                        (t "incomplete")))))


;;;###autoload
(defun aiaos-cli-provider--audit-read (name)
  "读取 NAME 的审计日志。"
  (let ((provider (aiaos-cli-provider--get name)))
    (if provider
        (aiaos-cli-provider--audit provider)
      nil)))


;;;###autoload
(defun aiaos-cli-provider--fallback-file ()
  "返回 fallback 配置文件路径。"
  (expand-file-name "provider-fallback.json" (aiaos-cli-provider--config-dir)))


;;;###autoload
(defun aiaos-cli-provider--load-fallback ()
  "加载 fallback 配置。

返回按优先级排序的 Provider 名称列表。"
  (let ((file (aiaos-cli-provider--fallback-file)))
    (if (file-readable-p file)
        (let ((data (with-temp-buffer
                      (insert-file-contents file)
                      (json-read-from-string (buffer-string)))))
          (if (hash-table-p data)
              (gethash "fallback-order" data)
            (cdr (assq 'fallback-order data))))
      nil)))


;;;###autoload
(defun aiaos-cli-provider--fallback-enabled ()
  "返回是否启用了 fallback 机制。"
  (let ((order (aiaos-cli-provider--load-fallback)))
    (and order (> (length order) 1) t)))


;;;###autoload
(defun aiaos-cli-provider--fallback-order ()
  "返回 fallback 顺序列表。"
  (aiaos-cli-provider--load-fallback))


;;;###autoload
(defun aiaos-cli-provider--fallback-set (order)
  "设置 fallback 顺序为 ORDER。

ORDER 是 Provider 名称列表。"
  (let ((file (aiaos-cli-provider--fallback-file)))
    (with-temp-file file
      (insert (json-encode (list :fallback-order order))))
    (aiaos-cli-log-info "Set fallback order: %s" order)
    order))


;;;###autoload
(defun aiaos-cli-provider--report ()
  "生成 Provider 使用报告。

返回 plist 包含统计信息。"
  (let ((providers (aiaos-cli-provider--list))
        (fallback-order (aiaos-cli-provider--fallback-order)))
    (list :total (length providers)
          :by-tier (seq-group-by (lambda (p) (plist-get p :tier)) providers)
          :fallback-enabled (aiaos-cli-provider--fallback-enabled)
          :fallback-order fallback-order)))


;;;###autoload
(defun aiaos-cli-provider--test (name)
  "测试 NAME Provider 的可用性。

返回 plist 包含 :status (ok/error) 和 :error。"
  (let* ((provider (aiaos-cli-provider--get name))
         (base-url (plist-get provider :base-url))
         (api-key (plist-get provider :api-key))
         (model (plist-get provider :model)))
    (cond
     ((null provider)
      (list :status "error" :error "Provider not found"))
     ((or (null base-url) (null api-key) (null model))
      (list :status "error" :error "Missing required fields"))
     (t
      ;; 占位实现：实际应该调用 API
      (list :status "ok" :base-url base-url :model model)))))


(provide 'aiaos-cli-provider)
;;; aiaos-cli-provider.el ends here
