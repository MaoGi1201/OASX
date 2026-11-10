# OASX 打包与发布流程

> 目的：把「改代码」「本机试用」「给别人发版」三件事分开，避免同版本多份包无法区分。



---

## 一、先分清四个动作

| 动作          | 做什么                 | 产物落在哪                                   | 频率      |
| ----------- | ------------------- | --------------------------------------- | ------- |
| **build**   | 编译出 Release 版       | `OASX\build\windows\x64\runner\Release` | 每次要试/要发 |
| **deploy**  | 把 Release 复制到本机安装目录 | `D:\Program Files\oasx`                 | 想在本机试新版 |
| **package** | 把 Release 压成 zip    | `OASX\oasx_v<版本>_windows.zip`           | 要发给别人   |
| **release** | 上传 zip + 打 tag      | Gitee 发行版                               | 正式发版    |

关键点：**deploy 只影响你自己这台机器，和发布无关**；发布看的是 zip 和 tag。

---

## 二、三条常用路径

### A. 日常改代码（最常用，不发版）

```bash
# 1. 确认分支
git branch --show-current          # 应该是 mine-dev

# 2. 提交并推送（不打 tag）
git add -A
git commit -m "fix(home): 修复 xxx"
git push origin mine-dev
```

需要在本机试效果时，再补一步：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\PythonProgram\build_oasx.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File D:\PythonProgram\deploy_oasx.ps1
```

`deploy_oasx.ps1` 会把旧的安装目录备份到 `D:\PythonProgram\oasx_backup_<时间戳>`，出问题可以整体拷回去。

---

### B. 同版本重发（版本号不变，只修了点东西）

> 适用：还是 0.3.22，但要替换 Gitee 上那个 zip。

```powershell
# 1. 先把 build 号 +1（pubspec.yaml 里 0.3.22+13 → 0.3.22+14）
#    这一步很重要：否则 exe 属性和上一包完全一样，事后无法区分
notepad D:\PythonProgram\OASX\pubspec.yaml

# 2. 构建 + 打包
powershell -NoProfile -ExecutionPolicy Bypass -File D:\PythonProgram\build_oasx.ps1

$release = 'D:\PythonProgram\OASX\build\windows\x64\runner\Release'
$asset   = 'D:\PythonProgram\OASX\oasx_v0.3.22_windows.zip'
if (Test-Path $asset) { Remove-Item $asset -Force }
Compress-Archive -Path (Join-Path $release '*') -DestinationPath $asset
```

1. 到 Gitee 发行版里**替换附件**（删旧的上传新的）。
2. 检查 exe 属性里的版本号是否已经是 `0.3.22+14`。
3. 提交 build 号的改动：

```bash
git add pubspec.yaml
git commit -m "chore(release): build 号 +1"
git push origin mine-dev
```

> ⚠️ 此时 tag `v0.3.22` 仍指向旧提交。如果你在意「tag 检出 = 包内容」，执行：  
> `git tag -f v0.3.22 && git push -f origin v0.3.22`  
> 不在意就跳过，但要记得 tag 和包不完全对应。

---

### C. 发新版本（推荐，最规范）

```bash
# 1. 改版本号：0.3.22+14 → 0.3.23+1
#    pubspec.yaml: version: 0.3.23+1 ；msix_version: 0.3.23.0

# 2. 更新 CHANGELOG.md 顶部，加 # v0.3.23 段落
#    然后重新生成 CHANGELATEST.md
python script/extract_changelog.py

# 3. 提交
git add pubspec.yaml CHANGELOG.md CHANGELATEST.md
git commit -m "chore(release): 版本号更新至 0.3.23"

# 4. 打 tag 并推送
git tag v0.3.23
git push origin mine-dev
git push origin v0.3.23
```

```powershell
# 5. 构建 + 打包
powershell -NoProfile -ExecutionPolicy Bypass -File D:\PythonProgram\build_oasx.ps1

$release = 'D:\PythonProgram\OASX\build\windows\x64\runner\Release'
$asset   = 'D:\PythonProgram\OASX\oasx_v0.3.23_windows.zip'
Compress-Archive -Path (Join-Path $release '*') -DestinationPath $asset
```

1. Gitee 上新建发行版，tag 选 `v0.3.23`，上传 zip，说明填 `CHANGELATEST.md` 内容。

---

## 三、发布前检查清单

- [ ] `git branch --show-current` 是 `mine-dev`（不是 `mine`）
- [ ] `flutter analyze` 无 issue、`flutter test` 全过（`build_oasx.ps1` 已包含）
- [ ] `pubspec.yaml` 的版本号符合本次发布意图（同版本重发也要 +1 build 号）
- [ ] CHANGELOG 已更新，`CHANGELATEST.md` 已重新生成
- [ ] zip 里的 `oasx.exe` 属性版本号正确
- [ ] 上传前先在本机 `deploy` 跑一遍，确认能启动

---

## 四、本地清理（可随时执行）

| 目录                                 | 占用       | 能否删         | 说明                          |
| ---------------------------------- | -------- | ----------- | --------------------------- |
| `OASX\build`                       | ~600 MB  | ✅ 可删        | 构建产物，下次 build 自动重建          |
| `OASX\.dart_tool`                  | ~130 MB  | ✅ 可删        | 依赖缓存，`flutter pub get` 自动重建 |
| `OASX-emu`                         | ~525 MB  | ⚠️ 看需要      | 之前的测试用克隆仓库，不用可整个删           |
| `D:\PythonProgram\flutter_sdk.zip` | 1.7 GB   | ✅ 可删        | Flutter SDK 安装包，SDK 已解压     |
| `oasx_backup_*`                    | ~33 MB/个 | ⚠️ 保留最近 1 个 | 本机安装目录的旧版备份，用于回滚            |
| `oasx_v*.zip`                      | ~15 MB   | ⚠️ 保留当前版本   | 发布包，上传后可留一份存档               |

一键清理构建产物：

```powershell
cd D:\PythonProgram\OASX
flutter clean
```

> `flutter clean` 会删掉 `build` 和 `.dart_tool`，之后第一次 build 会慢一点（要重新 `pub get`）。

---

## 五、常见坑

1. **忘了改 build 号** → 新旧包 exe 版本完全一样，出问题时无法判断用户装的是哪一版。
2. **`git add -A` 把 zip 提交进仓库** → 15 MB 二进制永久留在 git 历史里。建议 `.gitignore` 加一行 `oasx_v*.zip`。
3. **分支搞错** → 在 `mine` 上提交（那是旧分支，停在 035aece），推送后远端看不到。提交前先 `git branch --show-current`。
4. **同版本替换附件却不移动 tag** → tag 检出的是旧代码，和下载的包不一致。
5. **deploy 之前没 build** → `deploy_oasx.ps1` 会报 `Release build not found`。
