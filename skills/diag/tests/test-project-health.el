;;; lisp/skills/diag/tests/test-project-health.el --- 项目健康检查测试 -*- lexical-binding: t -*-

;;; Commentary:
;; R664: 测试 diag/project-health 命令的各项功能。
;; 覆盖场景：备份统计、文档检查、版本一致性、代码规模统计、TODO 计数。

;;; Code:
(require 'ert)
(require 'cl-lib)

(require 'aiaos-cli)
(aiaos-cli-initialize)

(require 'aiaos-cli-skill-diag/commands/project-health)

;;; Fixtures

(defvar aiaos-test-project-health--fixture-dir
  (expand-file-name "fixtures/test-project"
                    (file-name-directory load-file-name))
  "测试用的临时项目目录。")

(defun aiaos-test-project-health--setup ()
  "创建测试 fixture 目录。"
  (let* ((root-dir (expand-file-name "tmp-test-project" temporary-file-directory))
         (lisp-dir (expand-file-name "lisp" root-dir))
         (skills-dir (expand-file-name "lisp/skills" root-dir)))
    (make-directory root-dir t)
    (make-directory lisp-dir t)
    (make-directory skills-dir t)
    ;; 创建 VERSION 文件
    (with-temp-file (expand-file-name "VERSION" root-dir)
      (insert "1.0.0"))
    ;; 创建 CHANGELOG.md
    (with-temp-file (expand-file-name "CHANGELOG.md" root-dir)
      (insert "## [1.0.0]\n\n- Initial release\n"))
    ;; 创建 SKILL.md
    (with-temp-file (expand-file-name "SKILL.md" root-dir)
      (insert "Name: test-project\nVersion: 1.0.0\n"))
    ;; 创建 design.md
    (with-temp-file (expand-file-name "design.md" root-dir)
      (insert "# Test Project Design\n"))
    ;; 创建 README.md
    (with-temp-file (expand-file-name "README.md" root-dir)
      (insert "# Test Project\n"))
    ;; 创建 .aiaos-cli.json 配置文件
    (with-temp-file (expand-file-name ".aiaos-cli.json" root-dir)
      (insert "{\"version\":\"1.0.0\",\"skills\":[\"diag\"]}"))
    root-dir))

(defun aiaos-test-project-health--teardown (root-dir)
  "清理测试 fixture 目录。"
  (delete-directory (expand-file-name "lisp" root-dir) t)
  (delete-file (expand-file-name "VERSION" root-dir))
  (delete-file (expand-file-name "CHANGELOG.md" root-dir))
  (delete-file (expand-file-name "SKILL.md" root-dir))
  (delete-file (expand-file-name "design.md" root-dir))
  (delete-file (expand-file-name "README.md" root-dir))
  (delete-directory root-dir t))

;;; Tests: Backup counting

(ert-deftest aiaos-test-project-health--no-backups ()
  "测试无备份文件时返回 0。"
  (let ((root-dir (aiaos-test-project-health--setup)))
    (unwind-protect
        (let ((count (aiaos-diag-project-health--count-backups root-dir)))
          (should (= count 0)))
      (aiaos-test-project-health--teardown root-dir))))

(ert-deftest aiaos-test-project-health--with-backups ()
  "测试有备份文件时正确统计。"
  (let ((root-dir (aiaos-test-project-health--setup)))
    (unwind-protect
        (progn
          ;; 创建 3 个备份文件
          (with-temp-file (expand-file-name "test.bak.r600" root-dir) (insert ""))
          (with-temp-file (expand-file-name "old.bak.r500" root-dir) (insert ""))
          (with-temp-file (expand-file-name "another.bak.r650" root-dir) (insert ""))
          (let ((count (aiaos-diag-project-health--count-backups root-dir)))
            (should (= count 3))))
      (aiaos-test-project-health--teardown root-dir))))

;;; Tests: Documentation check

(ert-deftest aiaos-test-project-health--all-docs-present ()
  "测试所有文档存在时返回空列表。"
  (let ((root-dir (aiaos-test-project-health--setup)))
    (unwind-protect
        (let ((missing (aiaos-diag-project-health--check-docs root-dir)))
          (should (null missing)))
      (aiaos-test-project-health--teardown root-dir))))

(ert-deftest aiaos-test-project-health--missing-docs ()
  "测试缺失文档时正确返回。"
  (let ((root-dir (aiaos-test-project-health--setup)))
    (unwind-protect
        (progn
          (delete-file (expand-file-name "design.md" root-dir))
          (delete-file (expand-file-name "README.md" root-dir))
          (let ((missing (aiaos-diag-project-health--check-docs root-dir)))
            (should (member "design.md" missing))
            (should (member "README.md" missing))))
      (aiaos-test-project-health--teardown root-dir))))

;;; Tests: Version consistency

(ert-deftest aiaos-test-project-health--version-consistent ()
  "测试版本一致时无 issues。"
  (let ((root-dir (aiaos-test-project-health--setup)))
    (unwind-protect
        (let* ((result (aiaos-diag-project-health--check-version root-dir))
               (version (car result))
               (issues (cdr result)))
          (should (string= version "1.0.0"))
          (should (null issues)))
      (aiaos-test-project-health--teardown root-dir))))

(ert-deftest aiaos-test-project-health--version-mismatch ()
  "测试版本不一致时报告问题。"
  (let ((root-dir (aiaos-test-project-health--setup)))
    (unwind-protect
        (progn
          ;; 修改 CHANGELOG 版本
          (with-temp-file (expand-file-name "CHANGELOG.md" root-dir)
            (insert "## [1.0.1]\n\n- Fix\n"))
          (let* ((result (aiaos-diag-project-health--check-version root-dir))
                 (version (car result))
                 (issues (cdr result)))
            (should (string= version "1.0.0"))
            (should (not (null issues)))
            (should (member (format "VERSION(1.0.0) != CHANGELOG(1.0.1)")
                            issues))))
      (aiaos-test-project-health--teardown root-dir))))

(ert-deftest aiaos-test-project-health--missing-version-file ()
  "测试 VERSION 文件缺失时报告错误。"
  (let ((root-dir (aiaos-test-project-health--setup)))
    (unwind-protect
        (progn
          (delete-file (expand-file-name "VERSION" root-dir))
          (let* ((result (aiaos-diag-project-health--check-version root-dir))
                 (version (car result))
                 (issues (cdr result)))
            (should (null version))
            (should (member "VERSION 文件不存在" issues))))
      (aiaos-test-project-health--teardown root-dir))))

;;; Tests: Elisp statistics

(ert-deftest aiaos-test-project-health--elisp-stats ()
  "测试 Elisp 代码统计功能。"
  (let ((root-dir (aiaos-test-project-health--setup)))
    (unwind-protect
        (progn
          ;; 创建测试 .el 文件
          (let ((lisp-dir (expand-file-name "lisp" root-dir)))
            (with-temp-file (expand-file-name "test-module.el" lisp-dir)
              (insert "(defun test-function ()\n"
                      "  \"A test function.\"\n"
                      "  nil)\n\n"
                      "(defmacro test-macro ()\n"
                      "  \"A test macro.\"\n"
                      "  'nil)\n")))
          (let ((stats (aiaos-diag-project-health--count-elisp root-dir)))
            (should (> (car stats) 0))
            (should (>= (cadr stats) 2))))
      (aiaos-test-project-health--teardown root-dir))))

;;; Tests: TODO counting

(ert-deftest aiaos-test-project-health--count-todos ()
  "测试 TODO 标记统计功能。"
  (let ((root-dir (aiaos-test-project-health--setup)))
    (unwind-protect
        (progn
          ;; 创建包含 TODO 的 .el 文件
          (let ((lisp-dir (expand-file-name "lisp" root-dir)))
            (with-temp-file (expand-file-name "test-todos.el" lisp-dir)
              (insert ";; TODO: fix this\n"
                      "(defun test-todo ()\n"
                      "  ; FIXME: handle error\n"
                      "  (message \"TODO\")\n"
                      "  ;; TODO: add tests\n"
                      "  nil)\n")))
          (let ((counts (aiaos-diag-project-health--count-todos root-dir)))
            (should (plist-get counts :TODO))
            (should (plist-get counts :FIXME))))
      (aiaos-test-project-health--teardown root-dir))))

;;; Tests: Module count

(ert-deftest aiaos-test-project-health--count-modules ()
  "测试模块数量统计。"
  (let ((root-dir (aiaos-test-project-health--setup)))
    (unwind-protect
        (progn
          ;; 创建技能目录
          (make-directory (expand-file-name "lisp/skills/test-skill" root-dir) t)
          (make-directory (expand-file-name "lisp/skills/another-skill" root-dir) t)
          (let ((count (aiaos-diag-project-health--count-modules root-dir)))
            (should (= count 2))))
      (aiaos-test-project-health--teardown root-dir))))

;;; Tests: Main entry point

(ert-deftest aiaos-test-project-health--main-healthy ()
  "测试主入口在健康状态下返回正确结果。"
  (let ((root-dir (aiaos-test-project-health--setup)))
    (unwind-protect
        (let ((default-directory root-dir))
          (let* ((result (aiaos-cli-skill-diag/project-health '() '() nil))
                 (status (plist-get result :status))
                 (version (plist-get result :version))
                 (backup-count (plist-get result :backup-files)))
            (should (string= status "healthy"))
            (should (string= version "1.0.0"))
            (should (= backup-count 0))))
      (aiaos-test-project-health--teardown root-dir))))

(ert-deftest aiaos-test-project-health--main-with-warnings ()
  "测试主入口在有警告时返回 warning 状态。"
  (let ((root-dir (aiaos-test-project-health--setup)))
    (unwind-protect
        (progn
          ;; 添加大量备份文件触发 warning
          (dolist (i (number-sequence 1 51))
            (with-temp-file (expand-file-name (format "backup%d.bak.r%d" i i) root-dir) (insert "")))
          (let ((default-directory root-dir))
            (let* ((result (aiaos-cli-skill-diag/project-health '() '() nil))
                   (status (plist-get result :status)))
              (should (string= status "warning")))))
      (aiaos-test-project-health--teardown root-dir))))

(provide 'aiaos-test-project-health)
;;; test-project-health.el ends here
