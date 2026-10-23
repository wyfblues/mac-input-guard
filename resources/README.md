# Application icon / 应用图标

The default icon is a retro pixel monitor with a green screen and yellow padlock.
The artwork was generated with OpenAI's image generation tool and selected for
this project. It does not use SF Symbols or a third-party icon library.

`AppIcon.png` is the canonical artwork. To regenerate the multi-resolution macOS
icon, run from the repository root:

```sh
swift scripts/make-icon.swift resources/AppIcon.png resources/AppIcon.icns
```

The build requires and embeds `AppIcon.icns` in the signed application bundle.
The installer replaces the complete bundle and refreshes its macOS application
registration. Changing only a Desktop shortcut does not update a running app's
Dock icon. Re-signing an ad-hoc build can require the owner to approve
Accessibility and Keychain access again; changing the icon never resets the
protection password.

默认图标是复古像素显示器，搭配绿色屏幕和黄色小锁。图案使用 OpenAI 图像生成工具
创作，并由项目使用者选定，没有使用 SF Symbols 或第三方图标库。

`AppIcon.png` 是原始图案；在项目根目录运行上面的命令，可重新生成包含多种尺寸的
macOS 图标。构建时必须将 `AppIcon.icns` 写入签名后的应用包。安装脚本替换完整应用包，
并刷新 macOS 应用注册信息；只修改桌面快捷入口，不会同步修改正在运行的 App 的 Dock 图标。
临时签名的开发构建重新签名后，可能需要使用者再次确认辅助功能和钥匙串授权；
图标更新不会重置保护密码。
