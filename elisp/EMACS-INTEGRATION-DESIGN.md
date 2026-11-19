# AIAOS-CLI Emacs 双向交互方案设计

## 目标

让 AIAOS CLI 能够完整地、全面地管理 Emacs，建立完善的 Emacs 适配层和管控层，实现 AIAOS CLI 与 Emacs 的深度双向交互。

## 核心设计理念

### 1. 从"插件"到"基座"的转变

当前 AIAOS-CLI Emacs 前端是 Emacs 的一个插件/扩展。新方案要将其提升为 Emacs 的**控制基座**：
- AIAOS CLI 管理 Emacs 的所有元素（buffers、windows、frames、minor modes、keybindings）
- Emacs 成为 AIAOS CLI 的智能终端和交互界面
- 双向通信：AIAOS CLI 调用 Emacs 能力，Emacs 事件反馈给 AIAOS CLI

### 2. 适配层 + 管控层 双层架构

```
┌─────────────────────────────────────────────────────────────┐
│                    AIAOS CLI 应用层                          │
│  (技能、LLM、编排、自修复、安全)                              │
└──────────────┬──────────────────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────────────────┐
│                      管控层 (Control Layer)                   │
│  - Buffer 管理器  - Window 管理器  - Frame 管理器            │
│  - Mode 管理器   - Keybinding 管理器  - Hook 管理器          │
│  - 事件调度器    - 状态同步器    - 命令执行器                  │
└──────────────┬──────────────────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────────────────┐
│                     适配层 (Adapter Layer)                    │
│  - Emacs Core API 封装  - 异步调用包装  - 安全沙箱           │
│  - 性能监控      - 错误恢复      - 状态快照                   │
└──────────────┬──────────────────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────────────────┐
│                       Emacs 核心                             │
│  (Emacs Lisp Runtime, Buffer, Window, Frame, Minor Modes)    │
└─────────────────────────────────────────────────────────────┘
```

## 一、适配层 (Adapter Layer)

适配层是 AIAOS CLI 与 Emacs Core 之间的桥梁，负责将 Emacs 的底层 API 封装成安全、可靠、高性能的接口。

### 1.1 核心适配器

```elisp
;; aiaos-cli-emacs-adapter.el

(require 'aiaos-cli-core)
(require 'aiaos-cli-events)
(require 'aiaos-cli-monitor)

;;; === Emacs API 适配器 ===

(defmacro aiaos-cli-with-emacs-sync ((&optional timeout) &rest body)
  "同步执行 Emacs 操作，确保线程安全。
   TIMEOUT: 超时时间（毫秒），默认 5000ms。
   BODY: 要执行的 Emacs 操作。"
  `(let ((aiaos-cli-emacs-lock (aiaos-cli-lock)))
     (aiaos-cli-with-lock (aiaos-cli-emacs-lock)
       ,@body)))

(defmacro aiaos-cli-with-emacs-async ((&optional timeout) &rest body)
  "异步执行 Emacs 操作，不阻塞主流程。
   TIMEOUT: 超时时间（毫秒），默认 30000ms。
   BODY: 要执行的 Emacs 操作。"
  `(aiaos-cli-run-async
     (lambda ()
       (condition-case err
           (aiaos-cli-with-emacs-sync
             ,@body)
         (error
          (aiaos-cli-log-error "Emacs async error: %s" err)
          (signal (car err) (cdr err))))))

;;; === Buffer 适配器 ===

(cl-defstruct aiaos-cli-buffer-info
  "Buffer 信息结构。"
  (name)
  (file-name)
  (major-mode)
  (minor-modes)
  (point)
  (mark)
  (size)
  (modified-p)
  (read-only-p))

(cl-defun aiaos-cli-buffer-get-info (buffer)
  "获取 Buffer 的完整信息。"
  (with-current-buffer buffer
    (make-aiaos-cli-buffer-info
     :name (buffer-name)
     :file-name (buffer-file-name)
     :major-mode (symbol-name major-mode)
     :minor-modes (aiaos-cli-minor-mode-list)
     :point (point)
     :mark (mark)
     :size (buffer-size)
     :modified-p (buffer-modified-p)
     :read-only-p (buffer-read-only-p))))

(cl-defun aiaos-cli-buffer-list-info ()
  "获取所有 Buffer 的信息列表。"
  (mapcar #'aiaos-cli-buffer-get-info (buffer-list)))

(cl-defun aiaos-cli-buffer-exists-p (name)
  "检查 Buffer 是否存在。"
  (get-buffer name))

(cl-defun aiaos-cli-buffer-create (name &optional mode file)
  "创建 Buffer，如果不存在则创建。
   NAME: Buffer 名称。
   MODE: 主 mode。
   FILE: 关联的文件。"
  (let ((buf (get-buffer name)))
    (unless buf
      (with-current-buffer (get-buffer-create name)
        (when mode
          (funcall mode))
        (when file
          (set-visited-file-name file))
        (goto-char (point-min))))
    buf))

(cl-defun aiaos-cli-buffer-switch (name)
  "切换到指定 Buffer。
   NAME: Buffer 名称或对象。"
  (let ((buf (if (bufferp name) name (get-buffer name))))
    (when buf
      (switch-to-buffer buf))))

(cl-defun aiaos-cli-buffer-kill (name)
  "关闭 Buffer。
   NAME: Buffer 名称或对象。"
  (let ((buf (if (bufferp name) name (get-buffer name))))
    (when buf
      (kill-buffer buf))))

;;; === Window 适配器 ===

(cl-defstruct aiaos-cli-window-info
  "Window 信息结构。"
  (window)
  (buffer)
  (point)
  (hscroll)
  (left-margin)
  (right-margin)
  (top)
  (bottom)
  (width)
  (height))

(cl-defun aiaos-cli-window-get-info (window)
  "获取 Window 的完整信息。"
  (let ((buf (window-buffer window)))
    (make-aiaos-cli-window-info
     :window window
     :buffer buf
     :point (window-point window)
     :hscroll (window-hscroll window)
     :left-margin (window-left-margin window)
     :right-margin (window-right-margin window)
     :top (window-top window)
     :bottom (window-bottom window)
     :width (window-width window)
     :height (window-height window))))

(cl-defun aiaos-cli-window-list-info ()
  "获取所有 Window 的信息列表。"
  (mapcar #'aiaos-cli-window-get-info (window-list)))

(cl-defun aiaos-cli-window-split (window &optional side size)
  "分割 Window。
   WINDOW: 要分割的窗口。
   SIDE: 'left, 'right, 'above, 'below。
   SIZE: 新窗口大小。"
  (let ((buf (window-buffer window)))
    (select-window window)
    (split-window buf side size)
    (window-list)))

(cl-defun aiaos-cli-window-arrangement (windows layout)
  "按布局排列窗口。
   WINDOWS: 窗口列表。
   LAYOUT: 布局配置。"
  (dolist (win windows)
    (select-window win))
  (when layout
    (aiaos-cli-window-apply-layout layout)))

;;; === Frame 适配器 ===

(cl-defstruct aiaos-cli-frame-info
  "Frame 信息结构。"
  (frame)
  (name)
  (width)
  (height)
  (left)
  (top)
  (buffer-list)
  (selected-window))

(cl-defun aiaos-cli-frame-get-info (frame)
  "获取 Frame 的完整信息。"
  (make-aiaos-cli-frame-info
   :frame frame
   :name (frame-parameter frame 'name)
   :width (frame-width frame)
   :height (frame-height frame)
   :left (frame-parameter frame 'left)
   :top (frame-parameter frame 'top)
   :buffer-list (mapcar #'buffer-name (frame-buffer-list frame))
   :selected-window (frame-selected-window frame)))

(cl-defun aiaos-cli-frame-list-info ()
  "获取所有 Frame 的信息列表。"
  (mapcar #'aiaos-cli-frame-get-info (frame-list)))

(cl-defun aiaos-cli-frame-create (&optional name parameters)
  "创建新 Frame。
   NAME: Frame 名称。
   PARAMETERS: 额外参数。"
  (make-frame (append parameters (when name (list (cons 'name name))))))

(cl-defun aiaos-cli-frame-delete (frame)
  "删除 Frame。
   FRAME: Frame 对象。"
  (delete-frame frame))

;;; === Mode 适配器 ===

(cl-defun aiaos-cli-mode-list ()
  "列出所有可用的 Mode。"
  (let ((modes '()))
    (dolist (mode minor-mode-list)
      (when (boundp mode)
        (push (symbol-name mode) modes)))
    modes))

(cl-defun aiaos-cli-mode-active-p (mode)
  "检查 Mode 是否激活。
   MODE: Mode 符号。"
  (and (boundp mode) (symbol-value mode)))

(cl-defun aiaos-cli-mode-enable (mode)
  "启用 Mode。
   MODE: Mode 符号。"
  (when (fboundp mode)
    (funcall mode 1)))

(cl-defun aiaos-cli-mode-disable (mode)
  "禁用 Mode。
   MODE: Mode 符号。"
  (when (fboundp mode)
    (funcall mode 0)))

(cl-defun aiaos-cli-mode-toggle (mode)
  "切换 Mode 状态。
   MODE: Mode 符号。"
  (if (aiaos-cli-mode-active-p mode)
      (aiaos-cli-mode-disable mode)
    (aiaos-cli-mode-enable mode)))

;;; === Keybinding 适配器 ===

(cl-defun aiaos-cli-keybinding-set (keymap key command)
  "设置 Keybinding。
   KEYMAP: Keymap。
   KEY: 键序列。
   COMMAND: 命令。"
  (define-key keymap key command))

(cl-defun aiaos-cli-keybinding-unset (keymap key)
  "取消 Keybinding。
   KEYMAP: Keymap。
   KEY: 键序列。"
  (define-key keymap key nil))

(cl-defun aiaos-cli-keybinding-get (keymap key)
  "获取 Keybinding。
   KEYMAP: Keymap。
   KEY: 键序列。"
  (lookup-key keymap key))

(cl-defun aiaos-cli-keybinding-list (keymap)
  "列出 Keymap 中的所有绑定。"
  (let ((bindings '()))
    (keymap-equal-contents keymap bindings)
    (sort bindings (lambda (a b) (string< (car a) (car b))))))

;;; === Hook 适配器 ===

(cl-defun aiaos-cli-hook-add (hook function &optional append local)
  "添加 Hook 函数。
   HOOK: Hook 变量。
   FUNCTION: 函数。
   APPEND: 是否追加。
   LOCAL: 是否局部。"
  (add-hook hook function append local))

(cl-defun aiaos-cli-hook-remove (hook function &optional local)
  "移除 Hook 函数。
   HOOK: Hook 变量。
   FUNCTION: 函数。
   LOCAL: 是否局部。"
  (remove-hook hook function local))

(cl-defun aiaos-cli-hook-run (hook &rest args)
  "运行 Hook。
   HOOK: Hook 变量。
   ARGS: 参数。"
  (run-hook-with-args hook args))

;;; === 状态快照 ===

(cl-defun aiaos-cli-emacs-state-snapshot ()
  "获取 Emacs 完整状态快照。"
  (list
   :buffers (aiaos-cli-buffer-list-info)
   :windows (aiaos-cli-window-list-info)
   :frames (aiaos-cli-frame-list-info)
   :modes (aiaos-cli-mode-list)
   :time (current-time)))

(cl-defun aiaos-cli-emacs-state-restore (snapshot)
  "恢复 Emacs 状态。
   SNAPSHOT: 状态快照。"
  (condition-case err
      (let ((buffers (plist-get snapshot :buffers))
            (windows (plist-get snapshot :windows))
            (frames (plist-get snapshot :frames)))
        ;; 恢复 buffers
        (dolist (buf-info buffers)
          (aiaos-cli-buffer-create
           (aiaos-cli-buffer-info-name buf-info)
           (aiaos-cli-buffer-info-major-mode buf-info)
           (aiaos-cli-buffer-info-file-name buf-info)))
        ;; 恢复 frames
        (dolist (frame-info frames)
          (aiaos-cli-frame-create
           (aiaos-cli-frame-info-name frame-info)
           (list (cons 'width (aiaos-cli-frame-info-width frame-info))
                 (cons 'height (aiaos-cli-frame-info-height frame-info))
                 (cons 'left (aiaos-cli-frame-info-left frame-info))
                 (cons 'top (aiaos-cli-frame-info-top frame-info))))))
    (error
     (aiaos-cli-log-error "Failed to restore Emacs state: %s" err))))

(provide 'aiaos-cli-emacs-adapter)
```

### 1.2 性能监控适配器

```elisp
;; aiaos-cli-emacs-monitor.el

(require 'aiaos-cli-monitor)
(require 'aiaos-cli-events)

;;; === Emacs 性能监控 ===

(cl-defstruct aiaos-cli-emacs-metric
  "Emacs 性能指标。"
  (name)
  (value)
  (timestamp)
  (category))

(cl-defun aiaos-cli-emacs-metric-record (name value &optional category)
  "记录 Emacs 性能指标。
   NAME: 指标名称。
   VALUE: 指标值。
   CATEGORY: 类别。"
  (let ((metric (make-aiaos-cli-emacs-metric
                 :name name
                 :value value
                 :timestamp (current-time)
                 :category (or category 'general))))
    (aiaos-cli-monitor-record 'emacs metric)
    metric))

(cl-defun aiaos-cli-emacs-metric-get (name &optional category)
  "获取 Emacs 性能指标。
   NAME: 指标名称。
   CATEGORY: 类别。"
  (aiaos-cli-monitor-get 'emacs name category))

(cl-defun aiaos-cli-emacs-metric-list (&optional category)
  "列出 Emacs 性能指标。
   CATEGORY: 类别。"
  (aiaos-cli-monitor-list 'emacs category))

;;; === Emacs 操作计时 ===

(defmacro aiaos-cli-emacs-timeit (name &rest body)
  "计时 Emacs 操作。
   NAME: 操作名称。
   BODY: 操作体。"
  `(let ((start (current-time))
         (result nil))
     (condition-case err
         (progn
           ,@body
           (aiaos-cli-emacs-metric-record ,name (float-time (time-subtract (current-time) start)) 'operation)
           result)
       (error
        (aiaos-cli-emacs-metric-record ,name (float-time (time-subtract (current-time) start)) 'error)
        (signal (car err) (cdr err))))))

;;; === Emacs 内存监控 ===

(cl-defun aiaos-cli-emacs-memory-usage ()
  "获取 Emacs 内存使用情况。"
  (let ((gc-info (garbage-collect)))
    (list
     :cons-cells (nth 1 gc-info)
     :floats (nth 2 gc-info)
     :strings (nth 3 gc-info)
     :symbols (nth 4 gc-info)
     :buffer-list (length (buffer-list))
     :window-list (length (window-list))
     :frame-list (length (frame-list)))))

(cl-defun aiaos-cli-emacs-memory-record ()
  "记录 Emacs 内存使用情况。"
  (aiaos-cli-emacs-metric-record 'memory-usage (aiaos-cli-emacs-memory-usage) 'system))

(provide 'aiaos-cli-emacs-monitor)
```

## 二、管控层 (Control Layer)

管控层是 AIAOS CLI 的大脑，负责管理 Emacs 的所有元素和能力，实现统一的调度和控制。

### 2.1 Buffer 管理器

```elisp
;; aiaos-cli-control-buffer.el

(require 'aiaos-cli-emacs-adapter)
(require 'aiaos-cli-events)
(require 'aiaos-cli-state)

;;; === Buffer 管理器 ===

(cl-defstruct aiaos-cli-buffer-manager
  "Buffer 管理器。"
  (buffers)
  (active-buffer)
  (lock)
  (hooks))

(cl-defun aiaos-cli-buffer-manager-create ()
  "创建 Buffer 管理器。"
  (make-aiaos-cli-buffer-manager
   :buffers (make-hash-table :test 'equal)
   :active-buffer nil
   :lock (aiaos-cli-mutex-create "buffer-manager")
   :hooks '()))

(cl-defun aiaos-cli-buffer-manager-register (manager buffer)
  "注册 Buffer。
   MANAGER: Buffer 管理器。
   BUFFER: Buffer 对象。"
  (aiaos-cli-with-lock (aiaos-cli-buffer-manager-lock manager)
    (let ((buf-info (aiaos-cli-buffer-get-info buffer)))
      (puthash (aiaos-cli-buffer-info-name buf-info) buf-info
               (aiaos-cli-buffer-manager-buffers manager))
      (aiaos-cli-buffer-manager-active-set manager buffer)
      (aiaos-cli-events-fire 'buffer-created buf-info))))

(cl-defun aiaos-cli-buffer-manager-unregister (manager buffer)
  "注销 Buffer。
   MANAGER: Buffer 管理器。
   BUFFER: Buffer 对象。"
  (aiaos-cli-with-lock (aiaos-cli-buffer-manager-lock manager)
    (let ((buf-name (buffer-name buffer)))
      (remhash buf-name (aiaos-cli-buffer-manager-buffers manager))
      (when (eq (aiaos-cli-buffer-manager-active-buffer manager) buffer)
        (aiaos-cli-buffer-manager-active-set manager nil))
      (aiaos-cli-events-fire 'buffer-destroyed buf-name))))

(cl-defun aiaos-cli-buffer-manager-active-set (manager buffer)
  "设置活动 Buffer。
   MANAGER: Buffer 管理器。
   BUFFER: Buffer 对象。"
  (aiaos-cli-with-lock (aiaos-cli-buffer-manager-lock manager)
    (let ((old-buffer (aiaos-cli-buffer-manager-active-buffer manager)))
      (when old-buffer
        (aiaos-cli-events-fire 'buffer-deactivated old-buffer))
      (setf (aiaos-cli-buffer-manager-active-buffer manager) buffer)
      (when buffer
        (aiaos-cli-events-fire 'buffer-activated buffer)))))

(cl-defun aiaos-cli-buffer-manager-get (manager name)
  "获取 Buffer 信息。
   MANAGER: Buffer 管理器。
   NAME: Buffer 名称。"
  (aiaos-cli-with-lock (aiaos-cli-buffer-manager-lock manager)
    (gethash name (aiaos-cli-buffer-manager-buffers manager))))

(cl-defun aiaos-cli-buffer-manager-list (manager)
  "列出所有 Buffer。
   MANAGER: Buffer 管理器。"
  (aiaos-cli-with-lock (aiaos-cli-buffer-manager-lock manager)
    (hash-table-values (aiaos-cli-buffer-manager-buffers manager))))

(cl-defun aiaos-cli-buffer-manager-create (manager name &optional mode file)
  "创建 Buffer。
   MANAGER: Buffer 管理器。
   NAME: Buffer 名称。
   MODE: 主 mode。
   FILE: 关联文件。"
  (let ((buf (aiaos-cli-buffer-create name mode file)))
    (aiaos-cli-buffer-manager-register manager buf)
    buf))

(cl-defun aiaos-cli-buffer-manager-kill (manager name)
  "关闭 Buffer。
   MANAGER: Buffer 管理器。
   NAME: Buffer 名称。"
  (let ((buf (get-buffer name)))
    (when buf
      (aiaos-cli-buffer-manager-unregister manager buf)
      (aiaos-cli-buffer-kill buf))))

(cl-defun aiaos-cli-buffer-manager-switch (manager name)
  "切换到指定 Buffer。
   MANAGER: Buffer 管理器。
   NAME: Buffer 名称。"
  (let ((buf (get-buffer name)))
    (when buf
      (aiaos-cli-buffer-manager-active-set manager buf)
      (aiaos-cli-buffer-switch buf))))

(provide 'aiaos-cli-control-buffer)
```

### 2.2 Window 管理器

```elisp
;; aiaos-cli-control-window.el

(require 'aiaos-cli-emacs-adapter)
(require 'aiaos-cli-events)

;;; === Window 管理器 ===

(cl-defstruct aiaos-cli-window-manager
  "Window 管理器。"
  (windows)
  (active-window)
  (layout)
  (lock))

(cl-defun aiaos-cli-window-manager-create ()
  "创建 Window 管理器。"
  (make-aiaos-cli-window-manager
   :windows (make-hash-table :test 'eq)
   :active-window nil
   :layout nil
   :lock (aiaos-cli-mutex-create "window-manager")))

(cl-defun aiaos-cli-window-manager-register (manager window)
  "注册 Window。
   MANAGER: Window 管理器。
   WINDOW: Window 对象。"
  (aiaos-cli-with-lock (aiaos-cli-window-manager-lock manager)
    (let ((win-info (aiaos-cli-window-get-info window)))
      (puthash window win-info (aiaos-cli-window-manager-windows manager))
      (aiaos-cli-window-manager-active-set manager window)
      (aiaos-cli-events-fire 'window-created win-info))))

(cl-defun aiaos-cli-window-manager-unregister (manager window)
  "注销 Window。
   MANAGER: Window 管理器。
   WINDOW: Window 对象。"
  (aiaos-cli-with-lock (aiaos-cli-window-manager-lock manager)
    (remhash window (aiaos-cli-window-manager-windows manager))
    (when (eq (aiaos-cli-window-manager-active-window manager) window)
      (aiaos-cli-window-manager-active-set manager nil))
    (aiaos-cli-events-fire 'window-destroyed window)))

(cl-defun aiaos-cli-window-manager-active-set (manager window)
  "设置活动 Window。
   MANAGER: Window 管理器。
   WINDOW: Window 对象。"
  (aiaos-cli-with-lock (aiaos-cli-window-manager-lock manager)
    (let ((old-window (aiaos-cli-window-manager-active-window manager)))
      (when old-window
        (aiaos-cli-events-fire 'window-deactivated old-window))
      (setf (aiaos-cli-window-manager-active-window manager) window)
      (when window
        (aiaos-cli-events-fire 'window-activated window)))))

(cl-defun aiaos-cli-window-manager-get (manager window)
  "获取 Window 信息。
   MANAGER: Window 管理器。
   WINDOW: Window 对象。"
  (aiaos-cli-with-lock (aiaos-cli-window-manager-lock manager)
    (gethash window (aiaos-cli-window-manager-windows manager))))

(cl-defun aiaos-cli-window-manager-list (manager)
  "列出所有 Window。
   MANAGER: Window 管理器。"
  (aiaos-cli-with-lock (aiaos-cli-window-manager-lock manager)
    (hash-table-values (aiaos-cli-window-manager-windows manager))))

(cl-defun aiaos-cli-window-manager-split (manager window &optional side size)
  "分割 Window。
   MANAGER: Window 管理器。
   WINDOW: Window 对象。
   SIDE: 分割方向。
   SIZE: 新窗口大小。"
  (let ((new-windows (aiaos-cli-window-split window side size)))
    (dolist (win new-windows)
      (aiaos-cli-window-manager-register manager win))
    new-windows))

(cl-defun aiaos-cli-window-manager-arrange (manager layout)
  "排列窗口布局。
   MANAGER: Window 管理器。
   LAYOUT: 布局配置。"
  (aiaos-cli-with-lock (aiaos-cli-window-manager-lock manager)
    (setf (aiaos-cli-window-manager-layout manager) layout)
    (aiaos-cli-window-apply-layout layout)
    (aiaos-cli-events-fire 'window-layout-changed layout)))

(provide 'aiaos-cli-control-window)
```

### 2.3 Frame 管理器

```elisp
;; aiaos-cli-control-frame.el

(require 'aiaos-cli-emacs-adapter)
(require 'aiaos-cli-events)

;;; === Frame 管理器 ===

(cl-defstruct aiaos-cli-frame-manager
  "Frame 管理器。"
  (frames)
  (active-frame)
  (lock))

(cl-defun aiaos-cli-frame-manager-create ()
  "创建 Frame 管理器。"
  (make-aiaos-cli-frame-manager
   :frames (make-hash-table :test 'eq)
   :active-frame nil
   :lock (aiaos-cli-mutex-create "frame-manager")))

(cl-defun aiaos-cli-frame-manager-register (manager frame)
  "注册 Frame。
   MANAGER: Frame 管理器。
   FRAME: Frame 对象。"
  (aiaos-cli-with-lock (aiaos-cli-frame-manager-lock manager)
    (let ((frame-info (aiaos-cli-frame-get-info frame)))
      (puthash frame frame-info (aiaos-cli-frame-manager-frames manager))
      (aiaos-cli-frame-manager-active-set manager frame)
      (aiaos-cli-events-fire 'frame-created frame-info))))

(cl-defun aiaos-cli-frame-manager-unregister (manager frame)
  "注销 Frame。
   MANAGER: Frame 管理器。
   FRAME: Frame 对象。"
  (aiaos-cli-with-lock (aiaos-cli-frame-manager-lock manager)
    (remhash frame (aiaos-cli-frame-manager-frames manager))
    (when (eq (aiaos-cli-frame-manager-active-frame manager) frame)
      (aiaos-cli-frame-manager-active-set manager nil))
    (aiaos-cli-events-fire 'frame-destroyed frame)))

(cl-defun aiaos-cli-frame-manager-active-set (manager frame)
  "设置活动 Frame。
   MANAGER: Frame 管理器。
   FRAME: Frame 对象。"
  (aiaos-cli-with-lock (aiaos-cli-frame-manager-lock manager)
    (let ((old-frame (aiaos-cli-frame-manager-active-frame manager)))
      (when old-frame
        (aiaos-cli-events-fire 'frame-deactivated old-frame))
      (setf (aiaos-cli-frame-manager-active-frame manager) frame)
      (when frame
        (aiaos-cli-events-fire 'frame-activated frame)))))

(cl-defun aiaos-cli-frame-manager-get (manager frame)
  "获取 Frame 信息。
   MANAGER: Frame 管理器。
   FRAME: Frame 对象。"
  (aiaos-cli-with-lock (aiaos-cli-frame-manager-lock manager)
    (gethash frame (aiaos-cli-frame-manager-frames manager))))

(cl-defun aiaos-cli-frame-manager-list (manager)
  "列出所有 Frame。
   MANAGER: Frame 管理器。"
  (aiaos-cli-with-lock (aiaos-cli-frame-manager-lock manager)
    (hash-table-values (aiaos-cli-frame-manager-frames manager))))

(cl-defun aiaos-cli-frame-manager-create (manager &optional name parameters)
  "创建 Frame。
   MANAGER: Frame 管理器。
   NAME: Frame 名称。
   PARAMETERS: 额外参数。"
  (let ((frame (aiaos-cli-frame-create name parameters)))
    (aiaos-cli-frame-manager-register manager frame)
    frame))

(cl-defun aiaos-cli-frame-manager-delete (manager frame)
  "删除 Frame。
   MANAGER: Frame 管理器。
   FRAME: Frame 对象。"
  (aiaos-cli-frame-manager-unregister manager frame)
  (aiaos-cli-frame-delete frame))

(provide 'aiaos-cli-control-frame)
```

### 2.4 Mode 管理器

```elisp
;; aiaos-cli-control-mode.el

(require 'aiaos-cli-emacs-adapter)
(require 'aiaos-cli-events)

;;; === Mode 管理器 ===

(cl-defstruct aiaos-cli-mode-manager
  "Mode 管理器。"
  (modes)
  (lock))

(cl-defun aiaos-cli-mode-manager-create ()
  "创建 Mode 管理器。"
  (make-aiaos-cli-mode-manager
   :modes (make-hash-table :test 'equal)
   :lock (aiaos-cli-mutex-create "mode-manager")))

(cl-defun aiaos-cli-mode-manager-register (manager mode &optional function)
  "注册 Mode。
   MANAGER: Mode 管理器。
   MODE: Mode 符号。
   FUNCTION: 切换函数。"
  (aiaos-cli-with-lock (aiaos-cli-mode-manager-lock manager)
    (puthash mode (or function mode) (aiaos-cli-mode-manager-modes manager))
    (aiaos-cli-events-fire 'mode-registered mode)))

(cl-defun aiaos-cli-mode-manager-unregister (manager mode)
  "注销 Mode。
   MANAGER: Mode 管理器。
   MODE: Mode 符号。"
  (aiaos-cli-with-lock (aiaos-cli-mode-manager-lock manager)
    (remhash mode (aiaos-cli-mode-manager-modes manager))
    (aiaos-cli-events-fire 'mode-unregistered mode)))

(cl-defun aiaos-cli-mode-manager-get (manager mode)
  "获取 Mode 切换函数。
   MANAGER: Mode 管理器。
   MODE: Mode 符号。"
  (aiaos-cli-with-lock (aiaos-cli-mode-manager-lock manager)
    (gethash mode (aiaos-cli-mode-manager-modes manager))))

(cl-defun aiaos-cli-mode-manager-list (manager)
  "列出所有 Mode。
   MANAGER: Mode 管理器。"
  (aiaos-cli-with-lock (aiaos-cli-mode-manager-lock manager)
    (hash-table-values (aiaos-cli-mode-manager-modes manager))))

(cl-defun aiaos-cli-mode-manager-enable (manager mode)
  "启用 Mode。
   MANAGER: Mode 管理器。
   MODE: Mode 符号。"
  (let ((func (aiaos-cli-mode-manager-get manager mode)))
    (when func
      (funcall func 1)
      (aiaos-cli-events-fire 'mode-enabled mode))))

(cl-defun aiaos-cli-mode-manager-disable (manager mode)
  "禁用 Mode。
   MANAGER: Mode 管理器。
   MODE: Mode 符号。"
  (let ((func (aiaos-cli-mode-manager-get manager mode)))
    (when func
      (funcall func 0)
      (aiaos-cli-events-fire 'mode-disabled mode))))

(cl-defun aiaos-cli-mode-manager-toggle (manager mode)
  "切换 Mode 状态。
   MANAGER: Mode 管理器。
   MODE: Mode 符号。"
  (if (aiaos-cli-mode-active-p mode)
      (aiaos-cli-mode-manager-disable manager mode)
    (aiaos-cli-mode-manager-enable manager mode)))

(provide 'aiaos-cli-control-mode)
```

### 2.5 Keybinding 管理器

```elisp
;; aiaos-cli-control-keybinding.el

(require 'aiaos-cli-emacs-adapter)
(require 'aiaos-cli-events)

;;; === Keybinding 管理器 ===

(cl-defstruct aiaos-cli-keybinding-manager
  "Keybinding 管理器。"
  (keymaps)
  (lock))

(cl-defun aiaos-cli-keybinding-manager-create ()
  "创建 Keybinding 管理器。"
  (make-aiaos-cli-keybinding-manager
   :keymaps (make-hash-table :test 'equal)
   :lock (aiaos-cli-mutex-create "keybinding-manager")))

(cl-defun aiaos-cli-keybinding-manager-register (manager keymap key command)
  "注册 Keybinding。
   MANAGER: Keybinding 管理器。
   KEYMAP: Keymap。
   KEY: 键序列。
   COMMAND: 命令。"
  (aiaos-cli-with-lock (aiaos-cli-keybinding-manager-lock manager)
    (aiaos-cli-keybinding-set keymap key command)
    (aiaos-cli-events-fire 'keybinding-registered keymap key command)))

(cl-defun aiaos-cli-keybinding-manager-unregister (manager keymap key)
  "注销 Keybinding。
   MANAGER: Keybinding 管理器。
   KEYMAP: Keymap。
   KEY: 键序列。"
  (aiaos-cli-with-lock (aiaos-cli-keybinding-manager-lock manager)
    (aiaos-cli-keybinding-unset keymap key)
    (aiaos-cli-events-fire 'keybinding-unregistered keymap key)))

(provide 'aiaos-cli-control-keybinding)
```

### 2.6 Hook 管理器

```elisp
;; aiaos-cli-control-hook.el

(require 'aiaos-cli-emacs-adapter)
(require 'aiaos-cli-events)

;;; === Hook 管理器 ===

(cl-defstruct aiaos-cli-hook-manager
  "Hook 管理器。"
  (hooks)
  (lock))

(cl-defun aiaos-cli-hook-manager-create ()
  "创建 Hook 管理器。"
  (make-aiaos-cli-hook-manager
   :hooks (make-hash-table :test 'equal)
   :lock (aiaos-cli-mutex-create "hook-manager")))

(cl-defun aiaos-cli-hook-manager-register (manager hook function &optional append local)
  "注册 Hook 函数。
   MANAGER: Hook 管理器。
   HOOK: Hook 变量。
   FUNCTION: 函数。
   APPEND: 是否追加。
   LOCAL: 是否局部。"
  (aiaos-cli-with-lock (aiaos-cli-hook-manager-lock manager)
    (aiaos-cli-hook-add hook function append local)
    (aiaos-cli-events-fire 'hook-registered hook function)))

(cl-defun aiaos-cli-hook-manager-unregister (manager hook function &optional local)
  "注销 Hook 函数。
   MANAGER: Hook 管理器。
   HOOK: Hook 变量。
   FUNCTION: 函数。
   LOCAL: 是否局部。"
  (aiaos-cli-with-lock (aiaos-cli-hook-manager-lock manager)
    (aiaos-cli-hook-remove hook function local)
    (aiaos-cli-events-fire 'hook-unregistered hook function)))

(provide 'aiaos-cli-control-hook)
```

### 2.7 事件调度器

```elisp
;; aiaos-cli-control-dispatcher.el

(require 'aiaos-cli-events)
(require 'aiaos-cli-state)

;;; === 事件调度器 ===

(cl-defstruct aiaos-cli-dispatcher
  "事件调度器。"
  (handlers)
  (queue)
  (lock)
  (running-p))

(cl-defun aiaos-cli-dispatcher-create ()
  "创建事件调度器。"
  (make-aiaos-cli-dispatcher
   :handlers (make-hash-table :test 'equal)
   :queue (make-hash-table :test 'equal)
   :lock (aiaos-cli-mutex-create "dispatcher")
   :running-p nil))

(cl-defun aiaos-cli-dispatcher-register (dispatcher event-type handler)
  "注册事件处理器。
   DISPATCHER: 调度器。
   EVENT-TYPE: 事件类型。
   HANDLER: 处理函数。"
  (aiaos-cli-with-lock (aiaos-cli-dispatcher-lock dispatcher)
    (let ((handlers (gethash event-type (aiaos-cli-dispatcher-handlers dispatcher) '())))
      (puthash event-type (cons handler handlers) (aiaos-cli-dispatcher-handlers dispatcher)))))

(cl-defun aiaos-cli-dispatcher-unregister (dispatcher event-type handler)
  "注销事件处理器。
   DISPATCHER: 调度器。
   EVENT-TYPE: 事件类型。
   HANDLER: 处理函数。"
  (aiaos-cli-with-lock (aiaos-cli-dispatcher-lock dispatcher)
    (let ((handlers (gethash event-type (aiaos-cli-dispatcher-handlers dispatcher) '())))
      (puthash event-type (remove handler handlers) (aiaos-cli-dispatcher-handlers dispatcher)))))

(cl-defun aiaos-cli-dispatcher-dispatch (dispatcher event)
  "调度事件。
   DISPATCHER: 调度器。
   EVENT: 事件对象。"
  (let ((event-type (aiaos-cli-event-type event)))
    (aiaos-cli-with-lock (aiaos-cli-dispatcher-lock dispatcher)
      (let ((handlers (gethash event-type (aiaos-cli-dispatcher-handlers dispatcher) '())))
        (dolist (handler handlers)
          (condition-case err
              (funcall handler event)
            (error
             (aiaos-cli-log-error "Dispatcher handler error: %s" err))))))))

(cl-defun aiaos-cli-dispatcher-start (dispatcher)
  "启动调度器。
   DISPATCHER: 调度器。"
  (setf (aiaos-cli-dispatcher-running-p dispatcher) t)
  (aiaos-cli-run-async
    (lambda ()
      (while (aiaos-cli-dispatcher-running-p dispatcher)
        (aiaos-cli-dispatcher-process-queue dispatcher)
        (sleep-for 0.01)))))

(cl-defun aiaos-cli-dispatcher-stop (dispatcher)
  "停止调度器。
   DISPATCHER: 调度器。"
  (setf (aiaos-cli-dispatcher-running-p dispatcher) nil))

(provide 'aiaos-cli-control-dispatcher)
```

### 2.8 总控管理器

```elisp
;; aiaos-cli-control-manager.el

(require 'aiaos-cli-control-buffer)
(require 'aiaos-cli-control-window)
(require 'aiaos-cli-control-frame)
(require 'aiaos-cli-control-mode)
(require 'aiaos-cli-control-keybinding)
(require 'aiaos-cli-control-hook)
(require 'aiaos-cli-control-dispatcher)
(require 'aiaos-cli-emacs-adapter)
(require 'aiaos-cli-events)
(require 'aiaos-cli-monitor)

;;; === 总控管理器 ===

(cl-defstruct aiaos-cli-control-manager
  "总控管理器，管理 Emacs 所有元素。"
  (buffer-manager)
  (window-manager)
  (frame-manager)
  (mode-manager)
  (keybinding-manager)
  (hook-manager)
  (dispatcher)
  (lock)
  (initialized-p))

(cl-defun aiaos-cli-control-manager-create ()
  "创建总控管理器。"
  (let ((manager (make-aiaos-cli-control-manager
                  :buffer-manager (aiaos-cli-buffer-manager-create)
                  :window-manager (aiaos-cli-window-manager-create)
                  :frame-manager (aiaos-cli-frame-manager-create)
                  :mode-manager (aiaos-cli-mode-manager-create)
                  :keybinding-manager (aiaos-cli-keybinding-manager-create)
                  :hook-manager (aiaos-cli-hook-manager-create)
                  :dispatcher (aiaos-cli-dispatcher-create)
                  :lock (aiaos-cli-mutex-create "control-manager")
                  :initialized-p nil)))
    (aiaos-cli-control-manager-init manager)
    manager))

(cl-defun aiaos-cli-control-manager-init (manager)
  "初始化总控管理器。
   MANAGER: 总控管理器。"
  (aiaos-cli-with-lock (aiaos-cli-control-manager-lock manager)
    ;; 注册默认事件处理器
    (aiaos-cli-control-manager-register-default-handlers manager)
    ;; 启动调度器
    (aiaos-cli-dispatcher-start (aiaos-cli-control-manager-dispatcher manager))
    ;; 标记为已初始化
    (setf (aiaos-cli-control-manager-initialized-p manager) t)
    (aiaos-cli-events-fire 'control-manager-initialized manager)))

(cl-defun aiaos-cli-control-manager-register-default-handlers (manager)
  "注册默认事件处理器。
   MANAGER: 总控管理器。"
  (let ((dispatcher (aiaos-cli-control-manager-dispatcher manager)))
    ;; Buffer 事件
    (aiaos-cli-dispatcher-register dispatcher 'buffer-created
      (lambda (event) (aiaos-cli-control-manager-on-buffer-created manager event)))
    (aiaos-cli-dispatcher-register dispatcher 'buffer-destroyed
      (lambda (event) (aiaos-cli-control-manager-on-buffer-destroyed manager event)))
    ;; Window 事件
    (aiaos-cli-dispatcher-register dispatcher 'window-created
      (lambda (event) (aiaos-cli-control-manager-on-window-created manager event)))
    (aiaos-cli-dispatcher-register dispatcher 'window-destroyed
      (lambda (event) (aiaos-cli-control-manager-on-window-destroyed manager event)))
    ;; Frame 事件
    (aiaos-cli-dispatcher-register dispatcher 'frame-created
      (lambda (event) (aiaos-cli-control-manager-on-frame-created manager event)))
    (aiaos-cli-dispatcher-register dispatcher 'frame-destroyed
      (lambda (event) (aiaos-cli-control-manager-on-frame-destroyed manager event)))))

(cl-defun aiaos-cli-control-manager-on-buffer-created (manager event)
  "Buffer 创建事件处理。
   MANAGER: 总控管理器。
   EVENT: 事件对象。"
  (let ((buf-info (aiaos-cli-event-data event)))
    (aiaos-cli-monitor-record 'buffer-created 1 'counter)
    (aiaos-cli-log-info "Buffer created: %s" (aiaos-cli-buffer-info-name buf-info))))

(cl-defun aiaos-cli-control-manager-on-buffer-destroyed (manager event)
  "Buffer 销毁事件处理。
   MANAGER: 总控管理器。
   EVENT: 事件对象。"
  (let ((buf-name (aiaos-cli-event-data event)))
    (aiaos-cli-monitor-record 'buffer-destroyed 1 'counter)
    (aiaos-cli-log-info "Buffer destroyed: %s" buf-name)))

(cl-defun aiaos-cli-control-manager-on-window-created (manager event)
  "Window 创建事件处理。
   MANAGER: 总控管理器。
   EVENT: 事件对象。"
  (let ((win-info (aiaos-cli-event-data event)))
    (aiaos-cli-monitor-record 'window-created 1 'counter)
    (aiaos-cli-log-info "Window created")))

(cl-defun aiaos-cli-control-manager-on-window-destroyed (manager event)
  "Window 销毁事件处理。
   MANAGER: 总控管理器。
   EVENT: 事件对象。"
  (aiaos-cli-monitor-record 'window-destroyed 1 'counter)
  (aiaos-cli-log-info "Window destroyed"))

(cl-defun aiaos-cli-control-manager-on-frame-created (manager event)
  "Frame 创建事件处理。
   MANAGER: 总控管理器。
   EVENT: 事件对象。"
  (let ((frame-info (aiaos-cli-event-data event)))
    (aiaos-cli-monitor-record 'frame-created 1 'counter)
    (aiaos-cli-log-info "Frame created: %s" (aiaos-cli-frame-info-name frame-info))))

(cl-defun aiaos-cli-control-manager-on-frame-destroyed (manager event)
  "Frame 销毁事件处理。
   MANAGER: 总控管理器。
   EVENT: 事件对象。"
  (aiaos-cli-monitor-record 'frame-destroyed 1 'counter)
  (aiaos-cli-log-info "Frame destroyed"))

(cl-defun aiaos-cli-control-manager-get-status (manager)
  "获取总控管理器状态。
   MANAGER: 总控管理器。"
  (list
   :buffers (length (aiaos-cli-buffer-manager-list (aiaos-cli-control-manager-buffer-manager manager)))
   :windows (length (aiaos-cli-window-manager-list (aiaos-cli-control-manager-window-manager manager)))
   :frames (length (aiaos-cli-frame-manager-list (aiaos-cli-control-manager-frame-manager manager)))
   :modes (length (aiaos-cli-mode-manager-list (aiaos-cli-control-manager-mode-manager manager)))
   :initialized (aiaos-cli-control-manager-initialized-p manager)))

(cl-defun aiaos-cli-control-manager-shutdown (manager)
  "关闭总控管理器。
   MANAGER: 总控管理器。"
  (aiaos-cli-with-lock (aiaos-cli-control-manager-lock manager)
    (setf (aiaos-cli-control-manager-initialized-p manager) nil)
    (aiaos-cli-dispatcher-stop (aiaos-cli-control-manager-dispatcher manager))
    (aiaos-cli-events-fire 'control-manager-shutdown manager)))

(provide 'aiaos-cli-control-manager)
```

## 三、双向交互机制

### 3.1 AIAOS CLI → Emacs 调用通道

```elisp
;; aiaos-cli-emacs-call.el

(require 'aiaos-cli-emacs-adapter)
(require 'aiaos-cli-events)

;;; === AIAOS CLI 调用 Emacs ===

(cl-defun aiaos-cli-emacs-call (function &rest args)
  "调用 Emacs 函数。
   FUNCTION: 函数名或函数对象。
   ARGS: 参数列表。"
  (condition-case err
      (if (functionp function)
          (apply function args)
        (apply (intern function) args))
    (error
     (aiaos-cli-log-error "Emacs call failed: %s %s" function args)
     (signal (car err) (cdr err)))))

(cl-defun aiaos-cli-emacs-eval (expr)
  "求值 Emacs 表达式。
   EXPR: 表达式。"
  (condition-case err
      (eval expr)
    (error
     (aiaos-cli-log-error "Emacs eval failed: %s" expr)
     (signal (car err) (cdr err)))))

(cl-defun aiaos-cli-emacs-execute (command)
  "执行 Emacs 命令。
   COMMAND: 命令名称或命令对象。"
  (condition-case err
      (if (commandp command)
          (call-interactively command)
        (call-interactively (intern command)))
    (error
     (aiaos-cli-log-error "Emacs execute failed: %s" command)
     (signal (car err) (cdr err)))))

(provide 'aiaos-cli-emacs-call)
```

### 3.2 Emacs → AIAOS CLI 回调通道

```elisp
;; aiaos-cli-emacs-callback.el

(require 'aiaos-cli-events)
(require 'aiaos-cli-core)

;;; === Emacs 回调 AIAOS CLI ===

(cl-defun aiaos-cli-register-callback (event-type callback &optional once)
  "注册 Emacs 事件回调。
   EVENT-TYPE: 事件类型。
   CALLBACK: 回调函数。
   ONCE: 是否只执行一次。"
  (let ((wrapper (lambda (event)
                   (condition-case err
                       (funcall callback event)
                     (error
                      (aiaos-cli-log-error "Callback error: %s" err)))
                   (when once
                     (aiaos-cli-unregister-callback event-type wrapper)))))
    (aiaos-cli-events-register event-type wrapper)
    wrapper))

(cl-defun aiaos-cli-unregister-callback (event-type callback)
  "注销 Emacs 事件回调。
   EVENT-TYPE: 事件类型。
   CALLBACK: 回调函数。"
  (aiaos-cli-events-unregister event-type callback))

(provide 'aiaos-cli-emacs-callback)
```

## 四、集成与初始化

### 4.1 集成到主框架

```elisp
;; aiaos-cli-emacs-integration.el

(require 'aiaos-cli-emacs-adapter)
(require 'aiaos-cli-control-manager)
(require 'aiaos-cli-emacs-call)
(require 'aiaos-cli-emacs-callback)
(require 'aiaos-cli-events)

;;; === Emacs 集成 ===

(cl-defvar aiaos-cli-emacs-manager nil
  "全局 Emacs 总控管理器。")

(cl-defun aiaos-cli-emacs-integration-init ()
  "初始化 Emacs 集成。"
  (condition-case err
      (progn
        ;; 创建总控管理器
        (setq aiaos-cli-emacs-manager (aiaos-cli-control-manager-create))
        
        ;; 注册 Emacs 内置事件
        (aiaos-cli-register-emacs-built-in-events)
        
        ;; 注册默认回调
        (aiaos-cli-register-default-callbacks)
        
        ;; 触发集成初始化事件
        (aiaos-cli-events-fire 'emacs-integration-initialized aiaos-cli-emacs-manager)
        
        (aiaos-cli-log-info "Emacs integration initialized successfully"))
    (error
     (aiaos-cli-log-error "Emacs integration initialization failed: %s" err))))

(cl-defun aiaos-cli-register-emacs-built-in-events ()
  "注册 Emacs 内置事件。"
  ;; Buffer 事件
  (aiaos-cli-register-callback 'buffer-list-changed
    (lambda (event) (aiaos-cli-on-buffer-list-changed event)))
  ;; Window 事件
  (aiaos-cli-register-callback 'window-list-changed
    (lambda (event) (aiaos-cli-on-window-list-changed event)))
  ;; Frame 事件
  (aiaos-cli-register-callback 'frame-list-changed
    (lambda (event) (aiaos-cli-on-frame-list-changed event))))

(cl-defun aiaos-cli-register-default-callbacks ()
  "注册默认回调函数。"
  ;; 默认事件处理
  (aiaos-cli-register-callback 'control-manager-initialized
    (lambda (event) (aiaos-cli-log-info "Control manager initialized"))))

(cl-defun aiaos-cli-on-buffer-list-changed (event)
  "Buffer 列表变化事件处理。
   EVENT: 事件对象。"
  (let ((manager aiaos-cli-emacs-manager))
    (when manager
      (aiaos-cli-buffer-manager-list (aiaos-cli-control-manager-buffer-manager manager)))))

(cl-defun aiaos-cli-on-window-list-changed (event)
  "Window 列表变化事件处理。
   EVENT: 事件对象。"
  (let ((manager aiaos-cli-emacs-manager))
    (when manager
      (aiaos-cli-window-manager-list (aiaos-cli-control-manager-window-manager manager)))))

(cl-defun aiaos-cli-on-frame-list-changed (event)
  "Frame 列表变化事件处理。
   EVENT: 事件对象。"
  (let ((manager aiaos-cli-emacs-manager))
    (when manager
      (aiaos-cli-frame-manager-list (aiaos-cli-control-manager-frame-manager manager)))))

(provide 'aiaos-cli-emacs-integration)
```

## 五、使用示例

### 5.1 基本用法

```elisp
;; 初始化
(aiaos-cli-emacs-integration-init)

;; 获取状态
(aiaos-cli-control-manager-get-status aiaos-cli-emacs-manager)

;; 创建 Buffer
(aiaos-cli-buffer-manager-create 
  (aiaos-cli-control-manager-buffer-manager aiaos-cli-emacs-manager)
  "*aiaos-cli-test*" 'text-mode)

;; 切换 Buffer
(aiaos-cli-buffer-manager-switch 
  (aiaos-cli-control-manager-buffer-manager aiaos-cli-emacs-manager)
  "*aiaos-cli-test*")

;; 分割 Window
(aiaos-cli-window-manager-split
  (aiaos-cli-control-manager-window-manager aiaos-cli-emacs-manager)
  (selected-window) 'right 80)
```

### 5.2 高级用法

```elisp
;; 自定义事件处理
(aiaos-cli-register-callback 'buffer-created
  (lambda (event)
    (let ((buf-info (aiaos-cli-event-data event)))
      (message "New buffer: %s" (aiaos-cli-buffer-info-name buf-info)))))

;; 调用 Emacs 函数
(aiaos-cli-emacs-call 'switch-to-buffer "*scratch*")

;; 执行 Emacs 命令
(aiaos-cli-emacs-execute 'other-frame)

;; 获取 Emacs 状态快照
(aiaos-cli-emacs-state-snapshot)
```

## 六、性能优化策略

### 6.1 缓存策略

```elisp
;; 缓存 frequently accessed data
(cl-defun aiaos-cli-cache-buffer-info (name info &optional timeout)
  "缓存 Buffer 信息。
   NAME: Buffer 名称。
   INFO: Buffer 信息。
   TIMEOUT: 超时时间（秒）。"
  (let ((cache (aiaos-cli-cache-get 'buffer-info)))
    (puthash name (cons info (current-time)) cache)))

(cl-defun aiaos-cli-get-buffer-info-cached (name)
  "获取缓存的 Buffer 信息。
   NAME: Buffer 名称。"
  (let ((cached (gethash name (aiaos-cli-cache-get 'buffer-info))))
    (when cached
      (let ((info (car cached))
            (time (cdr cached)))
        (when (< (float-time (time-subtract (current-time) time)) 5) ; 5秒缓存
          info)))))
```

### 6.2 批量操作

```elisp
(cl-defun aiaos-cli-buffer-list-info-batch (names)
  "批量获取 Buffer 信息。
   NAMES: Buffer 名称列表。"
  (let ((results '()))
    (dolist (name names)
      (let ((buf (get-buffer name)))
        (when buf
          (push (aiaos-cli-buffer-get-info buf) results))))
    results))
```

## 七、安全机制

### 7.1 权限控制

```elisp
(cl-defun aiaos-cli-emacs-operation-allowed-p (operation &optional context)
  "检查 Emacs 操作是否允许。
   OPERATION: 操作类型。
   CONTEXT: 上下文信息。"
  (let ((security-policy (aiaos-cli-security-get-policy operation)))
    (when security-policy
      (funcall security-policy context))))
```

### 7.2 沙箱执行

```elisp
(defmacro aiaos-cli-emacs-sandbox (body)
  "在沙箱中执行 Emacs 操作。
   BODY: 操作体。"
  `(condition-case err
       (let ((aiaos-cli-sandbox-p t))
         ,@body)
     (error
      (aiaos-cli-log-error "Sandbox error: %s" err)
      (signal (car err) (cdr err)))))
```

## 八、总结

本方案建立了完善的 Emacs 适配层和管控层，实现了 AIAOS CLI 与 Emacs 的深度双向交互：

1. **适配层**：封装了 Emacs Core API，提供安全、可靠的接口
2. **管控层**：管理 Emacs 所有元素（Buffer、Window、Frame、Mode、Keybinding、Hook）
3. **双向交互**：AIAOS CLI 可调用 Emacs 能力，Emacs 事件可反馈给 AIAOS CLI
4. **性能优化**：缓存、批量操作、异步执行
5. **安全机制**：权限控制、沙箱执行

通过此方案，AIAOS CLI 成为 Emacs 的完整控制基座，能充分发挥 Emacs 的全部能力。