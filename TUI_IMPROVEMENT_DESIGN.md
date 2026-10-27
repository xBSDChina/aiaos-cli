# aiaos-cli TUI 企业级改进方案

> 基于 ratatui-kit 架构模式的 Elisp 前端重构设计

## 一、现状分析

### 1.1 aiaos-cli 当前架构

**技术栈：** Bash + Emacs Lisp (29.0+)

**核心模块：**
- `bin/aiaos-cli` - Bash 入口脚本
- `elisp/aiaos-cli.el` - Elisp 前端 (736 行)
- `core/*.sh` - 核心功能脚本 (agent, config, context, doctor, log, project, provider, session, skill)
- `skills/*` - 技能系统

**当前问题：**
1. **状态管理分散** - `defvar` 全局变量，无响应式更新机制
2. **组件化不足** - 函数式调用，无组件抽象层
3. **UI 能力有限** - 仅 buffer 输出，无交互式 TUI 组件
4. **依赖注入缺失** - 硬编码配置，无上下文管理
5. **异步处理简陋** - 基础 async-shell-command，无生命周期管理

### 1.2 ratatui-kit 核心架构模式

| 模式 | ratatui-kit 实现 | Elisp 映射 |
|------|----------------|-----------|
| **响应式状态** | `use_state` hook + `ReactiveHandle` | `aiaos-cli--state` + `cl-defun` |
| **依赖注入** | `Context` + `ContextStack` | `aiaos-cli--context` + `cl-defmacro` |
| **组件系统** | `#[component]` + `element!` | `aiaos-cli--component` + `cl-defmacro` |
| **生命周期** | `use_effect` + `use_on_drop` | `aiaos-cli--use-effect` + `unwind-protect` |
| **主题系统** | `Theme` + `ThemeProvider` | `aiaos-cli--theme` + `customize-group` |
| **路由系统** | `use_router` + `Router` | `aiaos-cli--router` + `aiaos-cli--page` |

---

## 二、改进方案

### 2.1 核心架构重构

#### 2.1.1 响应式状态管理系统

**设计目标：** 类 React useState 的响应式状态管理

```elisp
;;; aiaos-cli-state.el --- 响应式状态管理

(require 'cl-lib)
(require 'aiaos-cli-core)

(defgroup aiaos-cli-state nil
  "aiaos-cli 响应式状态管理"
  :group 'aiaos-cli)

;; 状态存储结构
(defstruct aiaos-cli--state
  "响应式状态容器"
  value      ; 当前值
  subscribers ; 订阅者列表
  locked     ; 防止并发修改
  )

;; 创建响应式状态
(cl-defmacro aiaos-cli--use-state (init-form &rest body)
  "创建响应式状态并返回 getter/setter。

示例:
  (let ((counter (aiaos-cli--use-state 0)))
    (list (aiaos-cli--state-get counter)
          (aiaos-cli--state-set counter 5)))"
  (declare (indent 1))
  `(let ((state (make-aiaos-cli--state :value ,init-form)))
     ,@body))

;; 获取状态值
(cl-defun aiaos-cli--state-get (state)
  "获取状态当前值"
  (aiaos-cli--state-value state))

;; 设置状态值
(cl-defun aiaos-cli--state-set (state value)
  "设置状态值并通知订阅者"
  (setf (aiaos-cli--state-value state) value)
  (aiaos-cli--state--notify state))

;; 订阅状态变化
(cl-defun aiaos-cli--state-subscribe (state callback)
  "订阅状态变化，返回取消订阅函数"
  (push callback (aiaos-cli--state-subscribers state))
  (lambda ()
    (setf (aiaos-cli--state-subscribers state)
          (delete callback (aiaos-cli--state-subscribers state)))))

;; 批量更新
(cl-defmacro aiaos-cli--state-batch (state &rest body)
  "批量更新状态，只触发一次通知"
  `(progn
     (setf (aiaos-cli--state-locked state) t)
     ,@body
     (setf (aiaos-cli--state-locked state) nil)
     (aiaos-cli--state--notify state)))
```

**关键特性：**
- ✅ 响应式更新自动触发重绘
- ✅ 支持批量更新减少渲染次数
- ✅ 订阅/取消订阅机制
- ✅ 线程安全（Emacs 单线程，但 async 回调需注意）

#### 2.1.2 依赖注入系统

**设计目标：** 类 React Context 的依赖注入

```elisp
;;; aiaos-cli-context.el --- 依赖注入系统

(require 'cl-lib)
(require 'aiaos-cli-state)

;; 上下文类型
(defstruct aiaos-cli--context
  "依赖注入上下文"
  parent     ; 父上下文
  values     ; 值哈希表
  )

;; 全局根上下文
(defvar aiaos-cli--root-context nil)

;; 创建上下文
(cl-defun aiaos-cli--context-create (parent)
  "创建新的上下文"
  (make-aiaos-cli--context
   :parent parent
   :values (make-hash-table :test 'equal)))

;; Provider 组件
(cl-defmacro aiaos-cli--context-provider (name value &rest body)
  "上下文提供者，类似 React Context.Provider"
  (declare (indent 2))
  `(let ((old-context aiaos-cli--current-context))
     (let ((new-context (aiaos-cli--context-create old-context)))
       (setf (gethash ,name new-context) ,value)
       (let ((aiaos-cli--current-context new-context))
         ,@body))))

;; Consumer 宏
(cl-defmacro aiaos-cli--context-consumer (name &rest body)
  "上下文消费者，获取指定上下文值"
  (declare (indent 1))
  `(gethash ,name (aiaos-cli--context--find aiaos-cli--current-context))

;; 查找上下文
(cl-defun aiaos-cli--context--find (context key)
  "在上下文链中查找值"
  (if (null context)
      nil
    (let ((value (gethash key (aiaos-cli--context-values context))))
      (if value
          value
        (aiaos-cli--context--find (aiaos-cli--context-parent context) key)))))

;; 初始化根上下文
(cl-defun aiaos-cli--context-init (&optional parent)
  "初始化根上下文"
  (setf aiaos-cli--root-context (aiaos-cli--context-create parent)))
```

**应用场景：**
- 全局配置注入
- 主题切换
- 多会话隔离
- 技能扩展点

#### 2.1.3 组件系统

**设计目标：** 类 React 组件的 UI 抽象

```elisp
;;; aiaos-cli-component.el --- 组件系统

(require 'cl-lib)
(require 'aiaos-cli-state)
(require 'aiaos-cli-context)

;; 组件结构
(defstruct aiaos-cli--component
  "UI 组件"
  name       ; 组件名称
  props      ; 属性
  state      ; 本地状态
  children   ; 子组件
  render     ; 渲染函数
  effects    ; 副作用列表
  )

;; 创建组件
(cl-defmacro aiaos-cli--component (name props &rest body)
  "定义组件"
  (declare (indent 2))
  `(cl-defun ,name (props)
     "组件函数"
     (let ((component (make-aiaos-cli--component
                         :name ',name
                         :props props
                         :state nil
                         :children nil
                         :effects nil)))
       ,@body
       component)))

;; 渲染组件
(cl-defun aiaos-cli--component-render (component)
  "渲染组件到指定 buffer"
  (with-current-buffer (generate-new-buffer "*aiaos-component*")
    (let ((inhibit-read-only t))
      (aiaos-cli--component--render-fn component (point))
      (buffer-string))))

;; 组件组合
(cl-defmacro aiaos-cli--compose (&rest components)
  "组合多个组件"
  `(aiaos-cli--component
    :name 'composed
    :props nil
    :render (lambda ()
              (mapc (lambda (comp)
                      (aiaos-cli--component-render comp))
                    ,components))))

;; HOC 高阶组件
(cl-defmacro aiaos-cli--with-state (state &rest body)
  "为组件注入状态"
  (declare (indent 1))
  `(let ((comp-state ,state))
     ,@body))

;; 示例：列表组件
(aiaos-cli--component aiaos-cli-list-component
  props
  (let ((items (aiaos-cli--prop props 'items))
        (selected (aiaos-cli--use-state nil)))
    (list :render
          (lambda (buffer)
            (dolist (item items)
              (when (= (car item) (aiaos-cli--state-get selected))
                (insert "▶ "))
              (insert (cadr item) "\n"))))))
```

**组件分类：**

| 组件类型 | 用途 | 对应 ratatui-kit |
|---------|------|----------------|
| **容器组件** | 布局、嵌套 | `View`, `Fragment` |
| **展示组件** | 纯展示 | `Text`, `Paragraph` |
| **交互组件** | 用户输入 | `Input`, `List`, `Modal` |
| **复合组件** | 复杂 UI | `Table`, `Router` |

#### 2.1.4 生命周期管理

**设计目标：** 类 React useEffect 的副作用管理

```elisp
;;; aiaos-cli-lifecycle.el --- 生命周期管理

(require 'cl-lib)

;; use-effect 宏
(cl-defmacro aiaos-cli--use-effect (deps &rest body)
  "注册副作用，deps 变化时执行"
  (declare (indent 1))
  `(progn
     ;; 注册到当前组件的 effects 列表
     (aiaos-cli--lifecycle--register-effect ,deps ,body)
     ;; 返回清理函数
     (lambda ()
       (aiaos-cli--lifecycle--cleanup-effect))))

;; use-on-drop 宏
(cl-defmacro aiaos-cli--use-on-drop (&rest body)
  "组件卸载时执行清理"
  (declare (indent 0))
  `(aiaos-cli--lifecycle--register-cleanup ,body))

;; 注册副作用
(cl-defun aiaos-cli--lifecycle--register-effect (deps body)
  "注册副作用到当前组件"
  (let ((comp (aiaos-cli--current-component)))
    (push (list :deps deps :body body :cleanup nil)
          (aiaos-cli--component-effects comp))))

;; 执行副作用
(cl-defun aiaos-cli--lifecycle--run-effects (comp)
  "执行组件的所有副作用"
  (dolist (effect (aiaos-cli--component-effects comp))
    (when (aiaos-cli--lifecycle--deps-changed effect)
      (funcall (cadr effect)))))

;; 清理副作用
(cl-defun aiaos-cli--lifecycle--cleanup-effect (&optional comp)
  "清理副作用"
  (dolist (effect (aiaos-cli--component-effects (or comp aiaos-cli--current-component)))
    (when (aiaos-cli--component-effect-cleanup effect)
      (funcall (aiaos-cli--component-effect-cleanup effect))
      (setf (aiaos-cli--component-effect-cleanup effect) nil))))
```

**生命周期阶段：**
1. **Mount** - 组件挂载时执行
2. **Update** - 状态变化时执行
3. **Unmount** - 组件卸载时清理

#### 2.1.5 主题系统

**设计目标：** 类 ratatui-kit Theme 的可定制主题

```elisp
;;; aiaos-cli-theme.el --- 主题系统

(require 'cl-lib)

;; 主题定义
(defstruct aiaos-cli--theme
  "UI 主题"
  name
  colors
  styles
  )

;; 预设主题
(defconst aiaos-cli--theme-dark
  (make-aiaos-cli--theme
   :name "dark"
   :colors '(:background "#081518"
             :foreground "#E8E3D5"
             :primary "#46C2C7"
             :secondary "#2E8A90"
             :accent "#FCA91C"
             :error "#FF6B6B"
             :success "#4ECB71"
             :warning "#FCA91C"
             :muted "rgba(232, 227, 213, 0.74)")
   :styles '((default . (:foreground foreground))
              (border . (:foreground secondary))
              (highlight . (:background primary :foreground background))
              (selected . (:background accent :foreground ink))
              (disabled . (:strike-through t :foreground muted)))))

(defconst aiaos-cli--theme-light
  (make-aiaos-cli--theme
   :name "light"
   :colors '(:background "#F4F0E6"
             :foreground "#1A1206"
             :primary "#2E8A90"
             :secondary "#46C2C7"
             :accent "#B06A05"
             :error "#C0392B"
             :success "#27AE60"
             :warning "#B06A05"
             :muted "rgba(26, 18, 6, 0.6)")
   :styles '((default . (:foreground foreground))
              (border . (:foreground secondary))
              (highlight . (:background primary :foreground background))
              (selected . (:background accent :foreground background))
              (disabled . (:strike-through t :foreground muted)))))

;; 主题 Provider
(cl-defmacro aiaos-cli--theme-provider (theme &rest body)
  "主题提供者"
  (declare (indent 1))
  `(aiaos-cli--context-provider 'theme ,theme
     (progn ,@body)))

;; 获取当前主题
(cl-defun aiaos-cli--theme-current ()
  "获取当前主题"
  (or (aiaos-cli--context-consumer 'theme)
      aiaos-cli--theme-dark))

;; 应用主题到 buffer
(cl-defun aiaos-cli--theme-apply (theme buffer)
  "应用主题到 buffer"
  (with-current-buffer buffer
    (set-background-color (cdr (assq :background (aiaos-cli--theme-colors theme))))
    (set-foreground-color (cdr (assq :foreground (aiaos-cli--theme-colors theme))))))
```

#### 2.1.6 路由系统

**设计目标：** 类 React Router 的页面路由

```elisp
;;; aiaos-cli-router.el --- 路由系统

(require 'cl-lib)
(require 'aiaos-cli-component)

;; 路由配置
(defstruct aiaos-cli--route
  "路由定义"
  path
  component
  params
  )

(defvar aiaos-cli--routes nil)
(defvar aiaos-cli--current-route nil)

;; 定义路由
(cl-defmacro aiaos-cli--define-routes (&rest routes)
  "定义路由表"
  `(setf aiaos-cli--routes
         '(,@routes)))

;; 导航
(cl-defun aiaos-cli--router-navigate (path)
  "导航到指定路径"
  (let ((route (aiaos-cli--router--match path)))
    (when route
      (setf aiaos-cli--current-route route)
      (aiaos-cli--router--render route))))

;; 匹配路由
(cl-defun aiaos-cli--router--match (path)
  "匹配路由"
  (dolist (route aiaos-cli--routes)
    (when (string= (aiaos-cli--route-path route) path)
      (return route))))

;; 渲染路由
(cl-defun aiaos-cli--router--render (route)
  "渲染路由组件"
  (let ((component (aiaos-cli--route-component route)))
    (aiaos-cli--component-render component)))

;; 示例
(aiaos-cli--define-routes
  (:path "/home" :component aiaos-cli-home-page)
  (:path "/skills" :component aiaos-cli-skills-page)
  (:path "/agent" :component aiaos-cli-agent-page)
  (:path "/settings" :component aiaos-cli-settings-page))
```

---

### 2.2 UI 组件库

#### 2.2.1 基础组件

```elisp
;;; aiaos-cli-components.el --- UI 组件库

(require 'aiaos-cli-component)
(require 'aiaos-cli-state)

;; 文本组件
(aiaos-cli--component aiaos-cli-text
  (props)
  (list :render
        (lambda (buffer)
          (insert (aiaos-cli--prop props 'text)))))

;; 边框组件
(aiaos-cli--component aiaos-cli-border
  (props)
  (let ((title (aiaos-cli--prop props 'title))
        (padding (aiaos-cli--prop props 'padding 1)))
    (list :render
          (lambda (buffer)
            (insert-char ?│ padding)
            (when title (insert " " title " "))
            (insert-char ?│ padding)
            (insert ?\n)))))

;; 列表组件
(aiaos-cli--component aiaos-cli-list
  (props)
  (let ((items (aiaos-cli--prop props 'items))
        (selected (aiaos-cli--use-state nil)))
    (list :render
          (lambda (buffer)
            (dolist (item items)
              (if (equal item (aiaos-cli--state-get selected))
                  (insert "▶ ")
                (insert "  "))
              (insert item "\n")))
          :on-select
          (lambda (item)
            (aiaos-cli--state-set selected item)))))
```

#### 2.2.2 交互组件

```elisp
;; 输入框组件
(aiaos-cli--component aiaos-cli-input
  (props)
  (let ((value (aiaos-cli--use-state (aiaos-cli--prop props 'value ""))))
    (list :render
          (lambda (buffer)
            (insert (aiaos-cli--state-get value)
                    (propertize " ┃" 'face 'aiaos-cli-input-cursor)))
          :on-change
          (lambda (text)
            (aiaos-cli--state-set value text)))))

;; 模态框组件
(aiaos-cli--component aiaos-cli-modal
  (props)
  (let ((visible (aiaos-cli--use-state t)))
    (list :render
          (lambda (buffer)
            (when (aiaos-cli--state-get visible)
              (insert (propertize (aiaos-cli--prop props 'title)
                                  'face 'aiaos-cli-modal-title)
                      "\n")
              (insert (aiaos-cli--prop props 'content) "\n")
              (insert "[Enter] 确认  [Esc] 取消\n"))))

;; 确认弹窗
(aiaos-cli--component aiaos-cli-confirm
  (props)
  (let ((confirmed (aiaos-cli--use-state nil)))
    (list :render
          (lambda (buffer)
            (insert "确认执行此操作吗？\n")
            (insert (aiaos-cli--prop props 'message) "\n")
            (insert (if (aiaos-cli--state-get confirmed)
                        "已确认" "未确认") "\n")))))
```

---

### 2.3 应用架构

#### 2.3.1 应用入口

```elisp
;;; aiaos-cli-app.el --- 应用主入口

(require 'aiaos-cli)
(require 'aiaos-cli-state)
(require 'aiaos-cli-context)
(require 'aiaos-cli-component)
(require 'aiaos-cli-lifecycle)
(require 'aiaos-cli-theme)
(require 'aiaos-cli-router)
(require 'aiaos-cli-components)

(defun aiaos-cli--app-init ()
  "初始化 aiaos-cli 应用"
  ;; 初始化根上下文
  (aiaos-cli--context-init)
  ;; 设置默认主题
  (aiaos-cli--theme-provider aiaos-cli--theme-dark
  ;; 定义路由
  (aiaos-cli--define-routes
    (:path "/" :component aiaos-cli-home-page)
    (:path "/skills" :component aiaos-cli-skills-page)
    (:path "/agent" :component aiaos-cli-agent-page))
  ;; 导航到首页
  (aiaos-cli--router-navigate "/"))

(defun aiaos-cli--app-run ()
  "运行 aiaos-cli 应用"
  (aiaos-cli--app-init)
  ;; 创建主 buffer
  (let ((buffer (get-buffer-create "*aiaos-cli*")))
    (with-current-buffer buffer
      (aiaos-cli-mode)
      (aiaos-cli--app-render))))

(defun aiaos-cli--app-render ()
  "渲染应用主界面"
  (let ((buffer (current-buffer)))
    (erase-buffer)
    ;; 渲染路由
    (aiaos-cli--router--render aiaos-cli--current-route)
    (goto-char (point-min))))
```

#### 2.3.2 页面组件

```elisp
;; 首页
(aiaos-cli--component aiaos-cli-home-page ()
  (list :render
        (lambda (buffer)
          (insert (propertize "AIAOS CLI" 'face 'aiaos-cli-title) "\n")
          (insert "==========\n\n")
          (insert "欢迎使用 AIAOS CLI\n\n")
          (insert "快捷键:\n")
          (insert "  C-c a h    帮助\n")
          (insert "  C-c a v    版本\n")
          (insert "  C-c a d    诊断\n")
          (insert "  C-c a s    会话管理\n")
          (insert "  C-c a k    技能管理\n")
          (insert "  C-c a a    代理聊天\n")
          (insert "  C-c a l    日志查看\n"))))

;; 技能管理页
(aiaos-cli--component aiaos-cli-skills-page ()
  (let ((skills (aiaos-cli-skill-list))
        (selected (aiaos-cli--use-state nil)))
    (list :render
          (lambda (buffer)
            (insert (propertize "技能管理" 'face 'aiaos-cli-title) "\n")
            (insert "==========\n\n")
            (dolist (skill skills)
              (if (equal skill (aiaos-cli--state-get selected))
                  (insert "▶ ")
                (insert "  "))
              (insert skill "\n"))))))
```

---

## 三、实施计划

### 阶段 1：基础设施 (1-2 周)
- [ ] 实现 `aiaos-cli-state.el` - 响应式状态
- [ ] 实现 `aiaos-cli-context.el` - 依赖注入
- [ ] 实现 `aiaos-cli-lifecycle.el` - 生命周期

### 阶段 2：组件系统 (2-3 周)
- [ ] 实现 `aiaos-cli-component.el` - 组件核心
- [ ] 实现 `aiaos-cli-theme.el` - 主题系统
- [ ] 实现 `aiaos-cli-components.el` - 基础组件

### 阶段 3：应用架构 (2-3 周)
- [ ] 实现 `aiaos-cli-router.el` - 路由系统
- [ ] 实现 `aiaos-cli-app.el` - 应用入口
- [ ] 重构 `aiaos-cli.el` - 迁移到新架构

### 阶段 4：高级组件 (3-4 周)
- [ ] 实现复杂交互组件
- [ ] 实现虚拟列表
- [ ] 实现表格组件

### 阶段 5：优化与文档 (2 周)
- [ ] 性能优化
- [ ] 单元测试
- [ ] 文档编写

---

## 四、兼容性与迁移

### 4.1 向后兼容
- 保留现有 `aiaos-cli.el` API
- 提供 `aiaos-cli-legacy.el` 兼容层
- 渐进式迁移

### 4.2 迁移策略
1. 新功能使用新架构
2. 旧功能逐步迁移
3. 提供迁移工具和脚本

---

## 五、风险与挑战

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| Elisp 性能限制 | 渲染速度 | 增量渲染、虚拟化 |
| 异步复杂度 | 竞态条件 | 状态锁、队列 |
| 学习曲线 | 开发效率 | 文档、示例、培训 |
| 生态迁移 | 第三方技能 | 兼容层、渐进迁移 |

---

## 六、总结

本方案借鉴 ratatui-kit 的企业级 TUI 架构，为 aiaos-cli 设计了完整的前端重构方案：

**核心价值：**
- ✅ 响应式状态管理 - 自动重绘
- ✅ 组件化开发 - 可复用 UI
- ✅ 依赖注入 - 灵活配置
- ✅ 主题系统 - 可定制 UI
- ✅ 路由系统 - 多页面支持
- ✅ 生命周期管理 - 资源安全

**技术债务：**
- Elisp 性能限制（需增量渲染优化）
- 异步复杂度（需严格状态管理）

**预期收益：**
- 开发效率提升 30%
- UI 一致性提升
- 可维护性提升
- 扩展性增强
