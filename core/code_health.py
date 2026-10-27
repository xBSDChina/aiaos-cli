#!/usr/bin/env python3
"""AIAOS-CLI 代码健康度检查工具（R2112 简化版）

检查项：
1. elisp/*.el: lexical-binding 声明
2. elisp/*.el: provide 声明
3. elisp/*.el: 版本号格式（如果有声明，必须符合 x.y.z）
4. elisp/*.el: defcustom/defgroup 配对
5. skills/*/commands/*.el: provide 声明（skills 命令是临时加载模块，不要求版本号）
"""
import os
import re
import sys

def check_elisp_file(filepath):
    """检查 elisp 核心模块"""
    issues = []
    
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 1. lexical-binding
    if 'lexical-binding' not in content:
        issues.append(f"{filepath}: 缺少 lexical-binding 声明")
    
    # 2. provide
    if '(provide' not in content:
        issues.append(f"{filepath}: 缺少 provide 声明")
    
    # 3. 版本号格式（如果有声明，必须符合 x.y.z）
    version_match = re.search(r';; Package-Version:\s*(\S+)', content)
    if version_match:
        version = version_match.group(1)
        if not re.match(r'^\d+\.\d+\.\d+$', version):
            issues.append(f"{filepath}: 版本号格式不规范: {version} (应为 x.y.z)")
    
    # 4. defcustom/defgroup 配对
    defcustom_count = len(re.findall(r'\(defcustom\)', content))
    defgroup_count = len(re.findall(r'\(defgroup\)', content))
    if defcustom_count > 0 and defgroup_count == 0:
        issues.append(f"{filepath}: 有 {defcustom_count} 个 defcustom 但缺少 defgroup")
    
    return issues

def check_skill_command(filepath):
    """检查 skills 命令文件（简化检查：只检查 provide）"""
    issues = []
    
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # skills 命令是临时加载模块，只检查 provide
    if '(provide' not in content:
        issues.append(f"{filepath}: 缺少 provide 声明")
    
    return issues

def main():
    elisp_dir = sys.argv[1]
    skills_dir = sys.argv[2]
    
    all_issues = []
    total_files = 0
    
    # 检查 elisp/*.el（核心模块，严格检查）
    if os.path.isdir(elisp_dir):
        for fname in sorted(os.listdir(elisp_dir)):
            if fname.endswith('.el'):
                filepath = os.path.join(elisp_dir, fname)
                total_files += 1
                all_issues.extend(check_elisp_file(filepath))
    
    # 检查 skills/*/commands/*.el（临时加载模块，简化检查）
    if os.path.isdir(skills_dir):
        for skill_dir in sorted(os.listdir(skills_dir)):
            commands_dir = os.path.join(skills_dir, skill_dir, 'commands')
            if os.path.isdir(commands_dir):
                for fname in sorted(os.listdir(commands_dir)):
                    if fname.endswith('.el'):
                        filepath = os.path.join(commands_dir, fname)
                        total_files += 1
                        all_issues.extend(check_skill_command(filepath))
    
    # 输出结果
    print(f"{len(all_issues)}|{total_files}|{chr(10).join(all_issues)}")

if __name__ == '__main__':
    main()
