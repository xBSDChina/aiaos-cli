;;; aiaos-cli-app.el --- 应用主入口 -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 1.0.0
;; Keywords: tools, process, aiaos, tui

;; 应用主入口，整合所有组件提供完整的 TUI 体验。
;; 基于 aiaos-cli-state, aiaos-cli-context, aiaos-cli-component 等模块构建。

;;; Commentary:

;; 本模块是 aiaos-cli 的 TUI 应用入口。
;; 主要功能：
;;   * aiaos-cli--app-init        - 初始化应用
;;   * aiaos-cli--app-run         - 运行应用
;;   * aiaos-cli--app-render      - 渲染应用界面
;;   * aiaos-cli--app-main-loop  - 主循环
;;   * aiaos-cli--app-quit       - 退出应用

;; R-FIX-READONLY: 修复 M-x aiaos 后 buffer is read-only 的问题。
;; 旧代码错误地 `(setq-local read-only nil)'，但控制 buffer 只读
;; 状态的变量是 `buffer-read-only'，`read-only' 是无关变量，导致
;; buffer 保持只读，用户输入即报 Buffer is read-only。
;; 现在正确设置 `buffer-read-only' 为 nil，并清理残留的
;; special-mode 只读文本属性。

;;; Code:

(require 'aiaos-cli-state)
(require 'aiaos-cli-context)
(require 'aiaos-cli-component)
(require 'aiaos-cli-lifecycle)
(require 'aiaos-cli-theme)
(require 'aiaos-cli-router)
(require 'aiaos-cli-command)
(require 'aiaos-cli-core)

;; ============================================================
;; 配置
;; ============================================================

(defcustom aiaos-cli-app-auto-refresh t
  "是否自动刷新界面"
  :type 'boolean
  :group 'aiaos-cli-app)

(defcustom aiaos-cli-app-refresh-interval 0.5
  "刷新间隔（秒）"
  :type 'number
  :group 'aiaos-cli-app)

(defcustom aiaos-cli-app-buffer-name "*aiaos-cli-app*"
  "应用主 buffer 名称"
  :type 'string
  :group 'aiaos-cli-app)

(defcustom aiaos-cli-app-show-statusbar t
  "是否显示状态栏"
  :type 'boolean
  :group 'aiaos-cli-app)

(defcustom aiaos-cli-app-show-sidebar t
  "是否显示侧边栏"
  :type 'boolean
  :group 'aiaos-cli-app)

(defcustom aiaos-cli-app-sidebar-width 30
  "侧边栏宽度"
  :type 'integer
  :group 'aiaos-cli-app)

;; ============================================================
;; 全局变量
;; ============================================================

(defvar aiaos-cli--app-buffer nil
  "应用主 buffer")

(defvar aiaos-cli--app-running nil
  "应用是否正在运行")

(defvar aiaos-cli--app-refresh-timer nil
  "刷新计时器")

(defvar aiaos-cli--app-components nil
  "应用组件列表")

;; ============================================================
;; 初始化应用
;; ============================================================

(defun aiaos-cli--app-init ()
  "初始化 aiaos-cli 应用"
  ;; 初始化各子系统
  (aiaos-cli--state-init)
  (aiaos-cli--context-init)
  (aiaos-cli--component-init)
  (aiaos-cli--lifecycle-init)
  (aiaos-cli--theme-init)
  (aiaos-cli--router-init)
  (aiaos-cli--app-register-routes)
  (aiaos-cli--app-load-sessions)
  (aiaos-cli--app-load-skills)
  (aiaos-cli--app-load-agents)
  (aiaos-cli--app-load-config)
  (aiaos-cli--app-init-keymap)
  (aiaos-cli--app-init-hooks))

;; ============================================================
;; 应用渲染
;; ============================================================

(defun aiaos-cli--app-render ()
  "渲染应用主界面

修复: 确保只在正确的 app buffer 中渲染，防止文本被粘贴到其他 buffer。
旧代码在 `aiaos-cli--app-buffer' 为 nil 时使用 `(current-buffer)'，
导致定时器回调可能在非 app buffer 中执行，错误粘贴文本。
现在添加 buffer 验证，如果 buffer 无效则不渲染。"
  (let* ((buffer aiaos-cli--app-buffer)
         (inhibit-read-only t))
    (if (and buffer (buffer-live-p buffer))
        (progn
          ;; 确保 buffer 可写
          (with-current-buffer buffer
            (setq buffer-read-only nil)
            ;; 清空 buffer
            (erase-buffer)
            ;; 应用主题
            (aiaos-cli--theme-apply (aiaos-cli--theme-current) buffer)
            ;; 渲染头部
            (aiaos-cli--app-render-header buffer)
            ;; 渲染导航栏
            (aiaos-cli--app-render-nav buffer)
            ;; 渲染当前路由
            (aiaos-cli--router-render (aiaos-cli--router-current) buffer)
            ;; 渲染状态栏
            (aiaos-cli--app-render-statusbar buffer)
            ;; 移动到开头
            (with-current-buffer buffer
              (goto-char (point-min)))
            buffer)
      ;; Buffer 无效，不渲染
      (aiaos-cli--log "warning" "App buffer not valid, skipping render")
      nil))))

;; 渲染头部
(defun aiaos-cli--app-render-header (buffer)
  "渲染头部

BUFFER 是目标 buffer"
  (with-current-buffer buffer
    (insert (propertize "AIAOS CLI" 'face 'aiaos-cli-app-title))
    (insert "  ")
    (insert (propertize (aiaos-cli--router-current-path) 'face 'aiaos-cli-app-subtitle))
    (insert "\n")
    (insert (make-string 80 ?-))
    (insert "\n")))

;; 渲染导航栏
(defun aiaos-cli--app-render-nav (buffer)
  "渲染导航栏

BUFFER 是目标 buffer"
  (with-current-buffer buffer
    (insert "导航: ")
    (insert (aiaos-cli--router-link "/" "首页"))
    (insert " | ")
    (insert (aiaos-cli--router-link "/overview" "总览"))
    (insert " | ")
    (insert (aiaos-cli--router-link "/skills" "技能"))
    (insert " | ")
    (insert (aiaos-cli--router-link "/agent" "代理"))
    (insert " | ")
    (insert (aiaos-cli--router-link "/settings" "设置"))
    (insert "\n")
    (insert (make-string 80 ?-))
    (insert "\n")))

;; 渲染状态栏
(defun aiaos-cli--app-render-statusbar (buffer)
  "渲染状态栏

BUFFER 是目标 buffer"
  (with-current-buffer buffer
    (insert (make-string 80 ?-))
    (insert "\n")
    (insert (propertize "AIAOS CLI" 'face 'aiaos-cli-app-title))
    (insert " | ")
    (insert (propertize "v1.0.0" 'face 'aiaos-cli-app-version))
    (insert " | ")
    (insert (propertize "按 C-c a 显示命令菜单" 'face 'aiaos-cli-app-help))
    (insert "\n")))

;; ============================================================
;; 页面组件
;; ============================================================

;; 首页
(defun aiaos-cli--app-page-home ()
  "创建首页组件"
  (let ((component (make-aiaos-cli--component :name 'home-page)))
    ;; 设置渲染函数
    (aiaos-cli--component-set-render component
          (lambda (buffer)
            (with-current-buffer buffer
              (insert "欢迎使用 AIAOS CLI\n\n")
              (insert "这是一个基于 ratatui-kit 架构的 TUI 应用。\n\n")
              (insert "主要功能:\n")
              (insert "  - 会话管理\n")
              (insert "  - 技能系统\n")
              (insert "  - 代理聊天\n")
              (insert "  - 日志查看\n")
              (insert "  - 环境诊断\n\n")
              (insert "快速开始:\n")
              (insert "  C-c a o    功能总览\n")
              (insert "  C-c a h    帮助\n")
              (insert "  C-c a a    代理聊天\n")
              (insert "  C-c a q    退出\n\n")
              (insert "提示: 使用 C-c a 显示命令菜单，浏览所有可用功能。\n")))
    component))

;; 功能总览
(defun aiaos-cli--app-page-overview ()
  "创建功能总览组件，按域分组展示全部交互式命令"
  (let ((component (make-aiaos-cli--component :name 'overview-page)))
    (aiaos-cli--component-set-render component
          (lambda (buffer)
            (with-current-buffer buffer
              (insert (propertize "功能总览" 'face 'aiaos-cli-app-title) "\n")
              (insert (make-string 40 ?-))
              (insert ?\n ?\n)
              (insert (propertize "会话管理 (session)" 'face 'aiaos-cli-app-title) "\n")
              (insert "  aiaos-cli-session-new      新建会话\n")
              (insert "  aiaos-cli-session-list     列出会话\n")
              (insert "  aiaos-cli-session-switch   切换会话\n")
              (insert "  aiaos-cli-session-show     显示当前会话\n")
              (insert "  aiaos-cli-session-archive  归档会话\n")
              (insert "  aiaos-cli-session-delete   删除会话\n\n")
              (insert (propertize "技能管理 (skill)" 'face 'aiaos-cli-app-title), "\n")
              (insert "  aiaos-cli-skill-list       列出技能\n")
              (insert "  aiaos-cli-skill-show       显示技能详情\n")
              (insert "  aiaos-cli-skill-toggle     启用/禁用技能\n")
              (insert "  aiaos-cli-skill-refresh    刷新技能缓存\n\n")
              (insert (propertize "代理聊天 (agent)" 'face 'aiaos-cli-app-title), "\n")
              (insert "  aiaos-cli-agent-list       列出代理\n")
              (insert "  aiaos-cli-agent-select     选择代理\n")
              (insert "  aiaos-cli-agent-chat       代理聊天\n")
              (insert "  aiaos-cli-agent-config     配置代理\n\n")
              (insert (propertize "设置 (settings)" 'face 'aiaos-cli-app-title), "\n")
              (insert "  aiaos-cli-settings-theme   主题设置\n")
              (insert "  aiaos-cli-settings-keybind 快捷键设置\n")
              (insert "  aiaos-cli-settings-reset   重置设置\n\n")
              (insert (propertize "诊断 (diagnostics)" 'face 'aiaos-cli-app-title), "\n")
              (insert "  aiaos-cli-doctor           运行诊断\n")
              (insert "  aiaos-cli-version          显示版本\n")
              (insert "  aiaos-cli-logs             查看日志\n\n")
              (insert (propertize "其他" 'face 'aiaos-cli-app-title), "\n")
              (insert "  C-c a l    日志查看\n")
              (insert "  C-c a t    切换主题\n")
              (insert "  C-c a r    刷新界面\n")
              (insert "  C-c a q    退出\n")
              (insert (make-string 40 ?-))
              (insert ?\n)
              (insert "提示: 点击下方命令名称可执行对应操作\n")
              (insert (propertize "aiaos-cli-session-new" 'face 'link) "\n")
              (insert (propertize "aiaos-cli-session-list" 'face 'link) "\n")
              (insert (propertize "aiaos-cli-session-switch" 'face 'link) "\n")
              (insert (propertize "aiaos-cli-skill-list" 'face 'link) "\n")
              (insert (propertize "aiaos-cli-agent-list" 'face 'link) "\n")
              (insert (propertize "aiaos-cli-doctor" 'face 'link) "\n")
              (insert (propertize "aiaos-cli-version" 'face 'link) "\n")
              (insert (propertize "aiaos-cli-logs" 'face 'link) "\n")
              (insert (make-string 40 ?-))
              (insert ?\n)
              (insert "LLM 对话\n")
              (insert (make-string 40 ?-))
              (insert ?\n)
              (insert "与 AI 进行对话，支持多 LLM provider 自动切换和错误自愈。\n")
              (insert "使用 C-c a a 或 M-x aiaos-cli-agent-chat 开始对话。\n")))))
    component))

;; 技能页
(defun aiaos-cli--app-page-skills ()
  "创建技能页组件"
  (let ((component (make-aiaos-cli--component :name 'skills-page)))
    (aiaos-cli--component-set-render component
          (lambda (buffer)
            (with-current-buffer buffer
              (insert (propertize "技能管理" 'face 'aiaos-cli-app-title) "\n")
              (insert (make-string 40 ?-))
              (insert ?\n)
              (insert "已安装的技能:\n\n")
              (if aiaos-cli--skill-cache
                  (dolist (skill aiaos-cli--skill-cache)
                    (insert "  ")
                    (insert (propertize skill 'face 'default))
                    (insert "\n"))
                (insert "  (暂无技能)\n")
                (insert "\n")
                (insert "使用 M-x aiaos-cli-skill-refresh 刷新技能列表。\n")))))
    component))

;; 代理页
(defun aiaos-cli--app-page-agent ()
  "创建代理页组件"
  (let ((component (make-aiaos-cli--component :name 'agent-page)))
    (aiaos-cli--component-set-render component
          (lambda (buffer)
            (with-current-buffer buffer
              (insert (propertize "LLM 对话" 'face 'aiaos-cli-app-title) "\n")
              (insert (make-string 40 ?-))
              (insert ?\n)
              (insert "与 AI 进行对话，支持多 LLM provider 自动切换和错误自愈。\n\n")
              (insert "当前 LLM provider 状态:\n")
              (let ((providers aiaos-llm-providers))
                (if providers
                    (dolist (provider providers)
                      (insert (format "  - %s: %s\n"
                                     (cdr (assq :name provider))
                                     (cdr (assq :status provider)))))
                  (insert "  (未配置 LLM provider)\n")))
              (insert "\n")
              (insert "Fallback 链: ")
              (if aiaos-fallback-chain
                  (insert (mapconcat 'identity aiaos-fallback-chain ", "))
                (insert "(未配置)"))
              (insert ?\n ?\n)
              (insert "使用 C-c a a 或 M-x aiaos-cli-agent-chat 开始对话。\n")
              (insert "使用 M-x aiaos-probe-all-providers 探测所有 provider 状态。\n")
              (insert "使用 M-x aiaos-build-fallback-chain 构建 fallback 链。\n"))))
    component))

;; 设置页
(defun aiaos-cli--app-page-settings ()
  "创建设置页组件"
  (let ((component (make-aiaos-cli--component :name 'settings-page)))
    (aiaos-cli--component-set-render component
          (lambda (buffer)
            (with-current-buffer buffer
              (insert (propertize "设置" 'face 'aiaos-cli-app-title) "\n")
              (insert (make-string 40 ?-))
              (insert ?\n)
              (insert "\n主题设置:\n")
              (insert "  当前主题: ")
              (insert (aiaos-cli--theme-name (aiaos-cli--theme-current)))
              (insert "\n  按 C-c a t 切换主题\n\n")
              (insert "其他设置:\n")
              (insert "  自动刷新: ")
              (insert (if aiaos-cli-app-auto-refresh "启用" "禁用"))
              (insert "\n"))))
    component))

;; ============================================================
;; 注册路由
;; ============================================================

(defun aiaos-cli--app-register-routes ()
  "注册应用路由"
  (aiaos-cli--router-add (aiaos-cli--router-create-route "/" (aiaos-cli--app-page-home)))
  (aiaos-cli--router-add (aiaos-cli--router-create-route "/overview" (aiaos-cli--app-page-overview)))
  (aiaos-cli--router-add (aiaos-cli--router-create-route "/skills" (aiaos-cli--app-page-skills)))
  (aiaos-cli--router-add (aiaos-cli--router-create-route "/agent" (aiaos-cli--app-page-agent)))
  (aiaos-cli--router-add (aiaos-cli--router-create-route "/settings" (aiaos-cli--app-page-settings)))
  (aiaos-cli--router-navigate "/")
  t)

;; ============================================================
;; 主模式
;; ============================================================

(defvar aiaos-cli--app-keymap
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "a") #'aiaos-cli-agent-chat)
    (define-key map (kbd "l") #'aiaos-cli-log-tail)
    (define-key map (kbd "q") #'aiaos-cli--app-quit)
    map)
  "aiaos-cli 应用子快捷键映射")

(defun aiaos-cli--app-quit ()
  "退出 aiaos-cli 应用"
  (interactive)
  (setq aiaos-cli--app-running nil)
  (when aiaos-cli--app-refresh-timer
    (cancel-timer aiaos-cli--app-refresh-timer)
    (setq aiaos-cli--app-refresh-timer nil))
  (let ((buf (or aiaos-cli--app-buffer
                 (get-buffer aiaos-cli-app-buffer-name))))
    (when (buffer-live-p buf)
      (kill-buffer buf))))

(defvar aiaos-cli-app-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c a") aiaos-cli--app-keymap)
    (define-key map (kbd "q") 'aiaos-cli--app-quit)
    map)
  "aiaos-cli 应用模式快捷键映射")

(defun aiaos-cli-app-mode ()
  "aiaos-cli 应用主模式

R-FIX-READONLY: 修复 M-x aiaos 后 buffer is read-only 的问题。
旧代码错误地 `(setq-local read-only nil)'，但控制 buffer 只读
状态的变量是 `buffer-read-only'，`read-only' 是无关变量，导致
buffer 保持只读，用户输入即报 Buffer is read-only。
现在正确设置 `buffer-read-only' 为 nil，并清理残留的
special-mode 只读文本属性。"
  (interactive)
  (kill-all-local-variables)
  (kill-local-variable 'mode-line-format)
  (setq mode-line-format " AIAOS CLI ")
  (make-local-variable 'aiaos-cli-app-mode-map)
  (local-set-key (kbd "C-c a") aiaos-cli--app-keymap)
  (local-set-key (kbd "q") 'aiaos-cli--app-quit)
  ;; 打开聊天窗口（与 LLM 交互的正确入口）
  (local-set-key (kbd "C-c C-c") 'aiaos-cli-agent-chat)
  (setq buffer-read-only nil)
  ;; 清除可能残留的只读文本属性
  (let ((inhibit-read-only t))
    (set-text-properties (point-min) (point-max) nil))
  (setq major-mode 'aiaos-cli-app-mode
        mode-name "aiaos-cli-app"))

;; ============================================================
;; 启动函数
;; ============================================================

;;;###autoload
(defun aiaos-cli--app-start ()
  "启动 aiaos-cli TUI 应用"
  (interactive)
  (unless (aiaos-cli--assert-binary)
    (user-error "aiaos-cli 未安装或不可执行"))
  ;; 检查版本
  (unless (aiaos-cli--version-consistent-p)
    (user-error "版本不匹配，请更新 aiaos-cli"))
  ;; 启动应用
  (aiaos-cli--app-run))

;;; Footer:

;; Local Variables:
;; folded-file: t
;; End:

(provide 'aiaos-cli-app)