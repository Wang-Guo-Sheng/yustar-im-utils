## Rime 撤消上屏
一键删除整词，然后重新选词，适用于打错字已经上屏之后返回修改，或者形码中打错字母后出现长短语需要反复退格的问题
- 模式一：按快捷键后删除整词，重新弹出输入框
- 模式二：删除后再按一次，自动上屏下一个候选

配合PowerToys快捷键映射，可以大幅减少修改错字耗时

用`rime-lua-sendKeyCode-main` （修改自 https://github.com/qiuyue0/rime-lua-sendKeyCode ）下用两个makefile分别编译一次，把生成的两个dll放在合适位置，dll目录粘贴到`cycle_select.lua`中
把脚本放在rime用户文件夹下的lua文件夹中，然后参考 `yustar_sc.schema.yaml`在方案schema中添加相应配置
