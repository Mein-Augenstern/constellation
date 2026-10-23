// star-site 小程序自动化示例：连接开发者工具 → 首页截图 → 进打卡页录一条血压
// 运行：node example-e2e.js   （需先 cli auto --auto-port 9420，且 dist 已构建）
const automator = require('miniprogram-automator')

async function main() {
  const miniProgram = await automator.connect({ wsEndpoint: 'ws://127.0.0.1:9420' })

  // 首页
  const page = await miniProgram.reLaunch('/pages/index/index')
  await page.waitFor(1000)
  await miniProgram.screenshot({ path: '/tmp/starsite-home.png' })

  // 进打卡页（血压预选）
  const metrics = await miniProgram.navigateTo('/pages/metrics/metrics?type=bp')
  await metrics.waitFor(800)
  await miniProgram.screenshot({ path: '/tmp/starsite-metrics.png' })

  await miniProgram.disconnect()
  console.log('done: /tmp/starsite-home.png, /tmp/starsite-metrics.png')
}

main().catch((e) => {
  console.error('automation failed:', e.message)
  process.exit(1)
})
