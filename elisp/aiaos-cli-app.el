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
;;   * aiaos-cli--app-quit        - 退出应用
;;   * aiaos-cli--app-main-loop   - 主循环

;;; Code:

(require 'cl-lib)

;; 循环依赖：aiaos-cli.el 已 require 本模块，故用 declare-function 声明
;; 仅使用 aiaos-cli-doctor / aiaos-cli-log-tail 两个函数
(declare-function aiaos-cli-doctor (aiaos-cli))
(declare-function aiaos-cli-log-tail (aiaos-cli))
(declare-function aiaos-cli--assert-binary (aiaos-cli))
(declare-function aiaos-cli--version-consistent-p (aiaos-cli))
(declare-function mouse-event-button-press-event-p (mouse))

(require 'aiaos-cli-state)
(require 'aiaos-cli-context)
(require 'aiaos-cli-component)
(require 'aiaos-cli-lifecycle)
(require 'aiaos-cli-theme)
(require 'aiaos-cli-router)
(require 'aiaos-cli-components)

(defvar aiaos-cli--expected-version "1.0.0")
(defvar aiaos-cli--skill-cache nil)

(defgroup aiaos-cli-app nil
  "aiaos-cli 应用"
  :group 'aiaos-cli
  :prefix "aiaos-cli-app-")

(defcustom aiaos-cli-app-buffer-name "*aiaos-cli*"
  "应用主 buffer 名称"
  :type 'string
  :group 'aiaos-cli-app)

(defcustom aiaos-cli-app-auto-refresh t
  "是否自动刷新界面"
  :type 'boolean
  :group 'aiaos-cli-app)

(defcustom aiaos-cli-app-refresh-interval 0.5
  "刷新间隔（秒）"
  :type 'number
  :group 'aiaos-cli-app)

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
  (aiaos-cli-components-init)
  ;; 设置默认主题
  (aiaos-cli--context-set :theme aiaos-cli--theme-dark)
  ;; 注册快捷键
  (aiaos-cli--app-bind-keys)
  t)

;; ============================================================
;; 运行应用
;; ============================================================

(defun aiaos-cli--app-run ()
  "运行 aiaos-cli 应用"
  ;; 初始化应用
  (aiaos-cli--app-init)
  ;; 创建主 buffer
  (let ((buffer (get-buffer-create aiaos-cli-app-buffer-name)))
    (with-current-buffer buffer
      (aiaos-cli-app-mode)
      ;; 渲染应用界面
      (aiaos-cli--app-render)
      ;; 开始主循环
      (aiaos-cli--app-main-loop buffer)))
  t)

;; ============================================================
;; 渲染应用界面
;; ============================================================

(defun aiaos-cli--app-render ()
  "渲染应用主界面"
  ;; 确保在正确的 buffer
  (let ((buffer (or aiaos-cli--app-buffer (current-buffer))))
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
    (goto-char (point-min))
    buffer))

;; 渲染头部
(defun aiaos-cli--app-render-header (buffer)
  "渲染应用头部

BUFFER 是目标 buffer"
  (with-current-buffer buffer
    ;; 渲染标题
    (insert (propertize "AIAOS CLI" 'face 'aiaos-cli-app-title) "\n")
    ;; 渲染副标题
    (insert (propertize "终端用户界面 - 基于 ratatui-kit 架构" 'face 'aiaos-cli-app-subtitle) "\n")
    ;; 渲染分隔线
    (insert (string 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552 9552))
    (insert ?\n)))

;; 渲染导航栏
(defun aiaos-cli--app-render-nav (buffer)
  "渲染导航栏

BUFFER 是目标 buffer"
  (with-current-buffer buffer
    ;; 渲染当前路由路径
    (let ((current (aiaos-cli--router-current)))
      (insert (propertize "路径: " 'face 'aiaos-cli-app-nav-label))
      (insert (propertize (aiaos-cli--route-path current) 'face 'aiaos-cli-app-nav-path))
      (insert "\n"))
    ;; 渲染导航链接
    (insert "导航: ")
    (insert (aiaos-cli--router-link "/overview" "总览"))
    (insert " | ")
    (insert (aiaos-cli--router-link "/" "首页"))
    (insert " | ")
    (insert (aiaos-cli--router-link "/skills" "技能"))
    (insert " | ")
    (insert (aiaos-cli--router-link "/agent" "代理"))
    (insert " | ")
    (insert (aiaos-cli--router-link "/settings" "设置"))
    (insert "\n")
    ;; 渲染分隔线
    (insert (make-string 80 ?-))
    (insert ?\n)))

;; 渲染状态栏
(defun aiaos-cli--app-render-statusbar (buffer)
  "渲染状态栏

BUFFER 是目标 buffer"
  (with-current-buffer buffer
    ;; 移动到 buffer 末尾
    (goto-char (point-max))
    ;; 确保在新行
    (insert ?\n)
    ;; 渲染状态栏组件
    (aiaos-cli--render-component
      (aiaos-cli-component-statusbar
        "就绪"
        (format "版本: %S" aiaos-cli--expected-version))
      buffer)))

;; ============================================================
;; 主循环
;; ============================================================

(defun aiaos-cli--app-main-loop (buffer)
  "应用主循环

BUFFER 是主 buffer"
  (setq aiaos-cli--app-running t)
  (setq aiaos-cli--app-buffer buffer)
  ;; 创建刷新计时器
  (when aiaos-cli-app-auto-refresh
    (setq aiaos-cli--app-refresh-timer
          (run-with-timer 1
                          aiaos-cli-app-refresh-interval
                          (lambda ()
                            (when (buffer-live-p buffer)
                              (with-current-buffer buffer
                                (aiaos-cli--app-render)))))))
  ;; 显示 buffer
  (switch-to-buffer buffer)
  ;; 进入递归编辑
  (recursive-edit))

;; ============================================================
;; 快捷键绑定
;; ============================================================

(defvar aiaos-cli--app-keymap
  (let ((map (make-sparse-keymap)))
    ;; 全局快捷键
    (define-key map (kbd "C-c a o") 'aiaos-cli--app-overview)
    (define-key map (kbd "C-c a h") 'aiaos-cli--app-help)
    (define-key map (kbd "C-c a v") 'aiaos-cli--app-version)
    (define-key map (kbd "C-c a d") 'aiaos-cli--app-doctor)
    (define-key map (kbd "C-c a s") 'aiaos-cli--app-sessions)
    (define-key map (kbd "C-c a k") 'aiaos-cli--app-skills)
    (define-key map (kbd "C-c a a") 'aiaos-cli--app-agent)
    (define-key map (kbd "C-c a l") 'aiaos-cli--app-logs)
    (define-key map (kbd "C-c a t") 'aiaos-cli--app-theme-toggle)
    (define-key map (kbd "C-c a r") 'aiaos-cli--app-refresh)
    (define-key map (kbd "C-c a q") 'aiaos-cli--app-quit)
    (define-key map (kbd "C-c a") 'aiaos-cli--app-command-menu)
    map)
  "aiaos-cli 应用快捷键映射")

(defun aiaos-cli--app-bind-keys ()
  "绑定快捷键"
  (define-key global-map (kbd "C-c a") aiaos-cli--app-keymap)
  t)

;; ============================================================
;; 快捷键处理函数
;; ============================================================

(defun aiaos-cli--app-overview ()
  "打开功能总览"
  (aiaos-cli--app-navigate "/overview"))

(defun aiaos-cli--app-help ()
  "显示帮助"
  (with-output-to-temp-buffer "*aiaos-cli-help*"
    (insert "AIAOS CLI 帮助\n")
    (insert "==========\n\n")
    (insert "快捷键:\n")
    (insert "  C-c a o    功能总览\n")
    (insert "  C-c a h    帮助\n")
    (insert "  C-c a v    版本\n")
    (insert "  C-c a d    诊断\n")
    (insert "  C-c a s    会话管理\n")
    (insert "  C-c a k    技能管理\n")
    (insert "  C-c a a    代理聊天\n")
    (insert "  C-c a l    日志查看\n")
    (insert "  C-c a t    切换主题\n")
    (insert "  C-c a r    刷新界面\n")
    (insert "  C-c a q    退出\n")
    (insert "  C-c a      命令菜单\n"))
  (display-buffer (get-buffer "*aiaos-cli-help*")))

(defun aiaos-cli--app-version ()
  "显示版本信息"
  (message "AIAOS CLI 版本: %S" aiaos-cli--expected-version))

(defun aiaos-cli--app-doctor ()
  "运行诊断"
  (aiaos-cli-doctor))

(defun aiaos-cli--app-sessions ()
  "打开会话管理"
  (aiaos-cli--app-navigate "/sessions"))

(defun aiaos-cli--app-skills ()
  "打开技能管理"
  (aiaos-cli--app-navigate "/skills"))

(defun aiaos-cli--app-agent ()
  "打开代理聊天"
  (aiaos-cli--app-navigate "/agent"))

(defun aiaos-cli--app-logs ()
  "查看日志"
  (aiaos-cli-log-tail))

(defun aiaos-cli--app-theme-toggle ()
  "切换主题"
  (let ((new-theme (aiaos-cli--theme-toggle)))
    (aiaos-cli--app-render)
    (message "已切换到 %S 主题" (aiaos-cli--theme-name new-theme))))

(defun aiaos-cli--app-refresh ()
  "刷新界面"
  (aiaos-cli--app-render))

(defun aiaos-cli--app-quit ()
  "退出应用"
  ;; 清理资源
  (aiaos-cli--lifecycle-cleanup-all)
  ;; 停止主循环
  (when aiaos-cli--app-refresh-timer
    (cancel-timer aiaos-cli--app-refresh-timer)
    (setq aiaos-cli--app-refresh-timer nil))
  (setq aiaos-cli--app-running nil)
  ;; 关闭 buffer
  (when (get-buffer aiaos-cli-app-buffer-name)
    (kill-buffer (get-buffer aiaos-cli-app-buffer-name)))
  ;; 退出递归编辑
  (exit-recursive-edit))

(defun aiaos-cli--app-command-menu ()
  "显示命令菜单"
  (let ((cmd (completing-read
              "命令: "
              '("help" "version" "doctor" "sessions" "skills" "agent" "logs" "theme" "refresh" "quit")
              nil nil nil)))
    (cond
      ((equal cmd "help") (aiaos-cli--app-help))
      ((equal cmd "version") (aiaos-cli--app-version))
      ((equal cmd "doctor") (aiaos-cli--app-doctor))
      ((equal cmd "sessions") (aiaos-cli--app-sessions))
      ((equal cmd "skills") (aiaos-cli--app-skills))
      ((equal cmd "agent") (aiaos-cli--app-agent))
      ((equal cmd "logs") (aiaos-cli--app-logs))
      ((equal cmd "theme") (aiaos-cli--app-theme-toggle))
      ((equal cmd "refresh") (aiaos-cli--app-refresh))
      ((equal cmd "quit") (aiaos-cli--app-quit)))))

;; ============================================================
;; 导航功能
;; ============================================================

(defun aiaos-cli--app-navigate (path)
  "导航到指定路径

PATH 是目标路径"
  (aiaos-cli--router-navigate path)
  (aiaos-cli--app-render))

;; ============================================================
;; 页面组件
;; ============================================================

;; 首页
(defun aiaos-cli--app-page-home ()
  "创建首页组件"
  (let ((component (make-aiaos-cli--component :name 'home-page)))
    ;; 设置渲染函数
    (setf (aiaos-cli--component-render component)
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
              (insert "使用 C-c a h 查看帮助\n"))))
    component))

;; 技能管理页
;; 功能总览页
(defun aiaos-cli--app-page-overview ()
  "创建功能总览组件，按域分组展示全部交互式命令"
  (let ((component (make-aiaos-cli--component :name 'overview-page)))
    (setf (aiaos-cli--component-render component)
          (lambda (buffer)
            (with-current-buffer buffer
              (insert "功能总览\n")
              (insert (make-string 60 ?-))
              (insert ?\n ?\n)
              (insert (propertize "会话管理 (session)" 'face 'aiaos-cli-app-title) "\n")
              (insert "  aiaos-cli-session-new      新建会话\n")
              (insert "  aiaos-cli-session-list     列出会话\n")
              (insert "  aiaos-cli-session-switch   切换会话\n")
              (insert "  aiaos-cli-session-show     显示当前会话\n")
              (insert "  aiaos-cli-session-archive  归档会话\n")
              (insert "  aiaos-cli-session-delete   删除会话\n")
              (insert "  aiaos-cli-session-current  显示当前会话\n")
              (insert ?\n ?\n)
              (insert (propertize "上下文操作 (context)" 'face 'aiaos-cli-app-title) "\n")
              (insert "  aiaos-cli-context-show     显示上下文\n")
              (insert "  aiaos-cli-context-save     保存上下文\n")
              (insert "  aiaos-cli-context-load     加载上下文\n")
              (insert "  aiaos-cli-context-clear    清空上下文\n")
              (insert "  aiaos-cli-context-export   导出上下文\n")
              (insert ?\n ?\n)
              (insert (propertize "技能管理 (skill)" 'face 'aiaos-cli-app-title) "\n")
              (insert "  aiaos-cli-skill-list       列出技能\n")
              (insert "  aiaos-cli-skill-info       查看技能信息\n")
              (insert "  aiaos-cli-skill-install    安装技能\n")
              (insert "  aiaos-cli-skill-uninstall  卸载技能\n")
              (insert "  aiaos-cli-skill-update     更新技能\n")
              (insert "  aiaos-cli-skill-search     搜索技能\n")
              (insert "  aiaos-cli-skill-validate   验证技能\n")
              (insert "  aiaos-cli-skill-run        运行技能\n")
              (insert "  aiaos-cli-skill-deps       查看技能依赖\n")
              (insert "  aiaos-cli-skill-create     创建技能\n")
              (insert "  aiaos-cli-skill-enable     启用技能\n")
              (insert "  aiaos-cli-skill-disable    停用技能\n")
              (insert "  aiaos-cli-skill-load       加载技能\n")
              (insert "  aiaos-cli-skill-load-all   加载全部技能\n")
              (insert ?\n ?\n)
              (insert (propertize "Agent 交互 (agent)" 'face 'aiaos-cli-app-title) "\n")
              (insert "  aiaos-cli-agent-chat       与 Agent 对话\n")
              (insert "  aiaos-cli-agent-delegate   委托 Agent\n")
              (insert "  aiaos-cli-agent-tool       调用 Agent 工具\n")
              (insert "  aiaos-cli-agent-history    查看 Agent 历史\n")
              (insert ?\n ?\n)
              (insert (propertize "项目管理 (project)" 'face 'aiaos-cli-app-title) "\n")
              (insert "  aiaos-cli-project-init     初始化项目\n")
              (insert "  aiaos-cli-project-sync     同步项目\n")
              (insert "  aiaos-cli-project-build    构建项目\n")
              (insert "  aiaos-cli-project-deploy   部署项目\n")
              (insert "  aiaos-cli-project-status   项目状态\n")
              (insert ?\n ?\n)
              (insert (propertize "配置管理 (config)" 'face 'aiaos-cli-app-title) "\n")
              (insert "  aiaos-cli-config-get       获取配置\n")
              (insert "  aiaos-cli-config-set       设置配置\n")
              (insert "  aiaos-cli-config-list      列出配置\n")
              (insert "  aiaos-cli-config-edit     编辑配置\n")
              (insert "  aiaos-cli-config-validate  验证配置\n")
              (insert "  aiaos-cli-config-migrate   迁移配置\n")
              (insert "  aiaos-cli-config-reset    重置配置\n")
              (insert ?\n ?\n)
              (insert (propertize "Provider 管理 (provider)" 'face 'aiaos-cli-app-title) "\n")
              (insert "  aiaos-cli-provider-list      列出 Provider\n")
              (insert "  aiaos-cli-provider-use       使用 Provider\n")
              (insert "  aiaos-cli-provider-chat      通过 Provider 对话\n")
              (insert "  aiaos-cli-provider-test     测试 Provider\n")
              (insert "  aiaos-cli-provider-fallback 设置 fallback\n")
              (insert "  aiaos-cli-provider-fallback-order 设置 fallback 顺序\n")
              (insert "  aiaos-cli-provider-tier     设置 Provider 层级\n")
              (insert "  aiaos-cli-provider-audit    审计 Provider\n")
              (insert "  aiaos-cli-provider-report   查看 Provider 报告\n")
              (insert ?\n ?\n)
              (insert (propertize "日志管理 (log)" 'face 'aiaos-cli-app-title) "\n")
              (insert "  aiaos-cli-log-tail         查看日志尾部\n")
              (insert "  aiaos-cli-log-tail-stop    停止 tail\n")
              (insert "  aiaos-cli-log-list         列出日志\n")
              (insert "  aiaos-cli-log-export       导出日志\n")
              (insert "  aiaos-cli-log-search       搜索日志\n")
              (insert "  aiaos-cli-log-analyze      分析日志\n")
              (insert ?\n ?\n)
              (insert (propertize "诊断与帮助 (doctor/help)" 'face 'aiaos-cli-app-title) "\n")
              (insert "  aiaos-cli-doctor          运行诊断\n")
              (insert "  aiaos-cli-doctor-fix      自动修复\n")
              (insert "  aiaos-cli-doctor-report   生成诊断报告\n")
              (insert "  aiaos-cli-help            显示帮助\n")
              (insert "  aiaos-cli-init            初始化系统\n")
              (insert "  aiaos-cli-version         显示版本\n")
              (insert ?\n ?\n)
              (insert "提示: M-x aiaos-cli-<command> 执行对应命令\n"))))
    component))

(defun aiaos-cli--app-page-skills ()
  "创建技能管理页组件"
  (let ((component (make-aiaos-cli--component :name 'skills-page)))
    ;; 设置渲染函数
    (setf (aiaos-cli--component-render component)
          (lambda (buffer)
            (with-current-buffer buffer
              (insert (propertize "技能管理" 'face 'aiaos-cli-app-title) "\n")
              (insert (make-string 40 ?-))
              (insert ?\n)
              ;; 列出已安装的技能
              (dolist (skill aiaos-cli--skill-cache)
                (insert "  ")
                (insert (propertize skill 'face 'default))
                (insert "\n"))
              (insert "\n按 C-c a k 刷新列表\n"))))
    component))

;; 代理聊天页
(defun aiaos-cli--app-page-agent ()
  "创建代理聊天页组件"
  (let ((component (make-aiaos-cli--component :name 'agent-page)))
    ;; 设置渲染函数
    (setf (aiaos-cli--component-render component)
          (lambda (buffer)
            (with-current-buffer buffer
              (insert (propertize "代理聊天" 'face 'aiaos-cli-app-title) "\n")
              (insert (make-string 40 ?-))
              (insert ?\n)
              (insert "\n开始与 AIAOS 代理对话...\n")
              (insert "\n按 C-c a a 打开聊天窗口\n"))))
    component))

;; 设置页
(defun aiaos-cli--app-page-settings ()
  "创建设置页组件"
  (let ((component (make-aiaos-cli--component :name 'settings-page)))
    ;; 设置渲染函数
    (setf (aiaos-cli--component-render component)
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

(defvar aiaos-cli-app-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c a") aiaos-cli--app-keymap)
    (define-key map (kbd "q") 'aiaos-cli--app-quit)
    map)
  "aiaos-cli 应用模式快捷键映射")

(defun aiaos-cli-app-mode ()
  "aiaos-cli 应用主模式"
  (interactive)
  (kill-local-variable 'mode-line-format)
  (setq mode-line-format " AIAOS CLI ")
  (make-local-variable 'aiaos-cli-app-mode-map)
  (local-set-key (kbd "C-c a") aiaos-cli--app-keymap)
  (local-set-key (kbd "q") 'aiaos-cli--app-quit))

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

;;; aiaos-cli-app.el ends here
(provide 'aiaos-cli-app)
