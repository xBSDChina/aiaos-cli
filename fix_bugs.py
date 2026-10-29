#!/usr/bin/env python3
"""Fix bugs in aiaos-cli-components.el"""

with open('elisp/aiaos-cli-components.el', 'r') as f:
    content = f.read()

# Bug 1: Fix extra paren in let* form
# Line 460: (is-selected (= idx (aiaos-cli--state-get selected-state))))
# The extra ) closes the let* body, making it empty
old_vlist = '(is-selected (= idx (aiaos-cli--state-get selected-state))))'
new_vlist = '(is-selected (= idx (aiaos-cli--state-get selected-state)))'
assert old_vlist in content, 'Bug pattern 1 not found!'
content = content.replace(old_vlist, new_vlist)

# Bug 2: Fix unused theme variable in component-shortcuts
old_sc = """(let ((component (make-aiaos-cli--component :name 'shortcuts))
        (theme (aiaos-cli--theme-current)))"""
new_sc = """(let ((component (make-aiaos-cli--component :name 'shortcuts)))"""
assert old_sc in content, 'Bug pattern 2 not found!'
content = content.replace(old_sc, new_sc)

# Bug 3: Fix unescaped single quotes in component-split docstring
old_doc = "  DIRECTION 是分割方向（'horizontal 或 'vertical，默认 'horizontal）"
new_doc = "  DIRECTION 是分割方向（\\\\'horizontal 或 \\\\'vertical，默认 \\\\'horizontal）"
if old_doc in content:
    content = content.replace(old_doc, new_doc)

with open('elisp/aiaos-cli-components.el', 'w') as f:
    f.write(content)

print('All 3 bugs fixed successfully')
