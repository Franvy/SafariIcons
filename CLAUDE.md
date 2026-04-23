# Tabnook

## 发版流程

**版本号**:改 `Tabnook.xcodeproj/project.pbxproj`,Debug 和 Release 两份 config 都要改
- `MARKETING_VERSION` → 对外版本 (如 `1.1.0`)
- `CURRENT_PROJECT_VERSION` → 构建号,每次递增

**Git**(标签和 Release 标题都用小写 `v`):
```bash
git commit -m "功能提交"
git commit -m "Bump version to X.Y.Z (build N)"
git tag -a vX.Y.Z -m "vX.Y.Z ..."
git push origin main && git push origin vX.Y.Z
```

**构建**(xcodebuild 和 gh 在 Claude 里需 `dangerouslyDisableSandbox`):
```bash
rm -rf build/Tabnook.xcarchive build/export build/RELEASE_NOTES.md

xcodebuild -project Tabnook.xcodeproj -scheme Tabnook \
  -configuration Release -archivePath build/Tabnook.xcarchive \
  -destination "generic/platform=macOS" clean archive

mkdir -p build/export
cp -R build/Tabnook.xcarchive/Products/Applications/Tabnook.app build/export/

create-dmg --volname "Tabnook X.Y.Z" --window-size 520 340 --icon-size 112 \
  --icon "Tabnook.app" 140 170 --hide-extension "Tabnook.app" \
  --app-drop-link 380 170 --no-internet-enable \
  build/Tabnook-X.Y.Z.dmg build/export/

shasum -a 256 build/Tabnook-X.Y.Z.dmg
```

**Release Notes** 写 `build/RELEASE_NOTES.md`,结构:What's new / Requirements / Install (含 Gatekeeper 绕过) / Privacy / Checksums / License

**发布**:
```bash
gh release create vX.Y.Z build/Tabnook-X.Y.Z.dmg \
  --title "vX.Y.Z" --notes-file build/RELEASE_NOTES.md
```

**注意**:ad-hoc 签名,不做公证;资源不要放 `Preview Content/`。

## Sparkle 自动更新

**首次设置**(每个开发者机器一次):
1. 在 Xcode 打开项目,等待 SPM 解析 Sparkle(`https://github.com/sparkle-project/Sparkle`)
2. 找到 Sparkle 产物的 `bin/generate_keys` 并生成 EdDSA 密钥对:
   ```bash
   SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData -name generate_keys -path '*/Sparkle_*/bin/*' | head -1)
   "$SPARKLE_BIN"     # 首次生成会把私钥存进 Keychain 并打印公钥
   ```
3. 把公钥写入 `Tabnook/Info.plist` 里 `SUPublicEDKey` 的 `<string>`(只有一处)
4. **备份私钥**:`"$SPARKLE_BIN" -x ~/Tabnook-eddsa-private.key`,放到安全的地方(1Password 等)。丢了就无法再发更新

**每次发版**(接在现有构建步骤之后):
```bash
SPARKLE_BIN_DIR=$(dirname "$(find ~/Library/Developer/Xcode/DerivedData -name sign_update -path '*/Sparkle_*/bin/*' | head -1)")

# 1. 用 sign_update 算出 DMG 的 EdDSA 签名
"$SPARKLE_BIN_DIR/sign_update" build/Tabnook-X.Y.Z.dmg
# 输出:sparkle:edSignature="..." length="..."

# 2. 手动在 appcast.xml 追加一个 <item>(见下方模板),或用 generate_appcast 自动生成
```

**appcast.xml `<item>` 模板**(追加到 `<channel>` 内):
```xml
<item>
    <title>X.Y.Z</title>
    <pubDate>RFC822 日期,如 Mon, 21 Apr 2026 12:00:00 +0000</pubDate>
    <sparkle:version>BUILD_NUMBER</sparkle:version>
    <sparkle:shortVersionString>X.Y.Z</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
    <description><![CDATA[release notes HTML]]></description>
    <enclosure
        url="https://github.com/Franvy/Tabnook/releases/download/vX.Y.Z/Tabnook-X.Y.Z.dmg"
        sparkle:edSignature="上一步 sign_update 输出"
        length="上一步 sign_update 输出"
        type="application/octet-stream" />
</item>
```

**最后**:把更新后的 `appcast.xml` 提交到 `main`(Sparkle 会从 raw.githubusercontent.com 拉取):
```bash
git add appcast.xml && git commit -m "Publish appcast for vX.Y.Z" && git push origin main
```

**注意**:
- Feed URL 已硬编码在 Info.plist:`https://raw.githubusercontent.com/Franvy/Tabnook/main/appcast.xml`
- `SUPublicEDKey` 必须填,否则 Sparkle 会拒绝未签名的更新
- 用户安装的旧版(没集成 Sparkle 前的 `v1.1.0` 及更早)不会自动升级,只有新版才会开始收到提醒
