# 两台 Windows 的 GitHub 协作

## 先明确当前边界

作品使用一个私有仓库 `anlogic-kids-learning-machine`，建在持板人的 GitHub 账号下。两人各自克隆，只有你负责板卡和最终合并确认。不要共享 Git 目录、ModelSim work 库、TD 缓存或密码。

本轮本机主目录仍有 21 项旧改动；工具升级在独立 `task/team-workflow`。下面涉及 main 的同步命令只在主目录干净、用户已确认旧改动处置后运行。不执行自动 stash、reset、clean 或覆盖。

## 第一次连接

1. 两人各有自己的 GitHub 账号，确认 Git、PowerShell 7.5+ 已安装。没有 GitHub CLI 时可用官方安装入口或 `winget install --id GitHub.cli --exact --source winget`；安装后新开终端核对 `gh --version`。
2. 本人运行 `gh auth login --hostname github.com --git-protocol https --web` 并在官方浏览器页面授权。不要将密码、PAT、设备授权后的令牌或 License 发给聊天/队友。
3. 总控确认当前认证账号后新建私有空仓库，不添加 GitHub 自动 README；先检查同名仓库是否已存在，存在则核对所有者、可见性和历史，不覆盖。
4. 首次只推送已经审查的现有 Git 提交作为远程 main 基线；工作目录里未提交的采购/学习成果不在这个上传范围内。
5. 推送 `task/team-workflow` 并建立 PR。本轮工具测试和权限策略提交必须可复核，main 合并等待你确认。
6. 通过仓库 Settings → Collaborators 邀请队友的真实 GitHub 用户名。对方接受后实际克隆，不能以“邀请已发送”代替“已经协作成功”。

GitHub CLI 不在 PATH 或尚未认证时是环境待办，不是流程通过。首次 bootstrap 可由总控使用系统 Git Credential Manager 官方设备登录完成认证；凭据只交给 GitHub 相关进程，不输出到日志。

## 队友的电脑

选择本机短 ASCII 工作区，例如 `D:/FPGA`。在该工作区克隆作品仓库，不要求也使用持板人的 E 盘。安装合法可用的 TD 6.2.1 和仿真器，记录实际版本与差异；先完成小模块复现，不必等待买第二块板。

建立工作区外层的 AGENTS、README、workspace-records 和 FILE_INDEX；规则参照项目 AGENTS 的交接流程，索引通过本机仓库 `tools/update-workspace-index.ps1 -WorkspaceRoot <本机工作区>` 生成。共享登记保留本机真实绝对路径，不复制另一台电脑的 JSON 当作自己的运行历史。没有本机规则、记录和通过的索引检查前，不运行自动提交入口。

仓库内日志和测试报告使用相对路径。正式工程的官方依赖写来源清单、版本和校验值；未经许可不把整套厂商安装包/IP/压缩包上传。教学区模块未获批准不能假装已经在正式仓库里。

## 每次开始

- 读取总控指定任务、最新任务卡和日志，确认自己是唯一写入者。
- 在干净主目录先 `git fetch origin`，再 `git pull --ff-only origin main`；失败停下调查，不强推或自动清理。
- 由总控先批准任务卡与分支日志，再使用 new-task-worktree 创建任务。该脚本不自动推送。
- 进入输出的 Worktree，确认 `git branch --show-current` 是自己的 task 分支。
- 完成一个小目标并记录真实验证，先只读检查范围，再显式提交；不要直接 `git add --all` 收进不相关文件。

具体检查、提交和验收参数见 [工具说明](../tools/README.md)。首轮升级尚未合入 main 时，普通新任务需等待 main 的可信任务卡；不能用自己的卡自行扩大权限。

## PR 的内容与合并

每个 PR 使用仓库模板，至少给出任务 ID、输入和策略基线、精确修改范围、HEAD、实际测试、原始证据链接/哈希、未验证层级和风险。

开发者先提交源码/说明，随后对该 HEAD 测试。生成的 runs 目录不再提交，否则 HEAD 改变，旧报告无法证明新版本。报告通过 PR 附件、Actions Artifact 或私有 Release 分享，附可下载位置与 SHA-256；只写个人磁盘路径不能作为跨电脑交付。

总控独立核查和必要复测后，向你显示待合并 SHA 与验收边界。你确认后通过 GitHub 的 Create a merge commit 合并，不用 squash/rebase 隐藏测试来源，不允许本地 merge 后再推主干。

账号支持时为 main 设置：必须 PR、至少一名其他成员审查、必要检查通过、禁止强推和删除。保护功能受账号/仓库方案限制；未能启用时保留团队约定并明确不具备服务器强制保护，不能声称自动安全。

## 第一个队友 PR

任务使用 `learning-assets`，只建立 14 个 item_id 的素材索引和来源说明，不改 HDL、不改接口、不接外设。检查数量、编号、中文/拼音/英文、文件引用和授权来源；没有的素材如实写待准备，不伪造完成。

队友解释一项自己检查过的对应关系；总控审查后由你确认合并。目标是完整走通领取、提交、验收、PR、同步，不追求第一个 PR 就写复杂 RTL。

## 发布与每天收尾

每周只发布真实验收过的镜像：源代码提交、TD 版本、资源/时序、镜像 SHA-256、重编译/烧录说明和已知问题。二进制镜像放 GitHub 私有 Release，不让 Git 历史不断积累大型构建文件。

你每天交一份上板现象与镜像信息，队友交一份复现或素材检查记录，总控更新状态。状态分为文件/模块/工程/上板/发布，不用 GitHub 绿色勾代替硬件验证。

不建立后台定时巡检；需要继续时在主对话说“开始今天这一轮”。
