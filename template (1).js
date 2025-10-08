// 脚本功能：解析 Sing-box 订阅，将节点按正则规则分配到指定出站组
// 支持组合订阅或单订阅，自动插入 COMPATIBLE(direct) 防止空出站组报错
// 参数说明：
//   - type: 订阅类型（collection 或 subscription）
//   - name: 订阅名称
//   - outbound: 出站组匹配规则（如 🕳ℹ️all|all-auto🏷ℹ️.*）
//   - includeUnsupportedProxy: 是否包含 SSR 等不支持的协议（true/false）
//   - url: 可选的订阅 URL（需 encodeURIComponent）

console.log('🚀 [Sing-box 模板脚本] 开始执行');

// 参数验证
const { type = 'subscription', name, outbound, includeUnsupportedProxy = false, url } = $arguments;
if (!name || !outbound) {
  throw new Error('❌ 缺少必要参数：name 和 outbound 不能为空');
}
const subType = /^1$|col|组合/i.test(type) ? 'collection' : 'subscription';
console.log(`📋 参数：type=${subType}, name=${name}, outbound=${outbound}, includeUnsupportedProxy=${includeUnsupportedProxy}${url ? `, url=${url}` : ''}`);

// 解析配置文件
const parser = ProxyUtils.JSON5 || JSON;
console.log(`📄 使用 ${ProxyUtils.JSON5 ? 'JSON5' : 'JSON'} 解析配置文件`);
let config;
try {
  config = parser.parse($content ?? $files[0]);
  if (!config.outbounds || !Array.isArray(config.outbounds)) {
    throw new Error('配置文件缺少 outbounds 数组');
  }
} catch (e) {
  console.error(`❌ 解析配置文件失败：${e.message}`);
  throw new Error(`配置文件不是合法的 ${ProxyUtils.JSON5 ? 'JSON5' : 'JSON'} 格式`);
}

// 获取订阅节点
async function fetchProxies() {
  try {
    const opts = {
      name,
      type: subType,
      platform: 'sing-box',
      produceType: 'internal',
      produceOpts: {
        'include-unsupported-proxy': includeUnsupportedProxy,
      },
    };
    if (url) {
      opts.subscription = { name, url, source: 'remote' };
      console.log(`🌐 从 URL 获取订阅：${url}`);
    } else {
      console.log(`🌐 获取 ${subType === 'collection' ? '组合' : ''}订阅：${name}`);
    }
    const proxies = await produceArtifact(opts);
    if (!proxies || proxies.length === 0) {
      throw new Error('订阅未返回任何节点');
    }
    return proxies;
  } catch (e) {
    console.error(`❌ 获取订阅失败：${e.message}`);
    throw e;
  }
}

// 解析出站规则
console.log('🛠️ 解析 outbound 规则');
const outboundRules = outbound
  .split('🕳')
  .filter(Boolean)
  .map(rule => {
    const [outboundPattern, tagPattern = '.*'] = rule.split('🏷');
    const tagRegex = createRegex(tagPattern);
    const outboundRegex = createRegex(outboundPattern);
    console.log(`🕳 匹配 ${outboundRegex} 的出站组，将插入 🏷 ${tagPattern} 的节点`);
    return { outboundRegex, tagRegex, outboundPattern };
  });

// 验证出站组是否存在
const configOutboundTags = new Set(config.outbounds.map(o => o.tag));
outboundRules.forEach(({ outboundRegex, outboundPattern }) => {
  const matched = config.outbounds.some(o => outboundRegex.test(o.tag));
  if (!matched) {
    console.warn(`⚠️ 出站规则 ${outboundPattern} 未匹配到配置文件中的任何出站组`);
  }
});

// 插入节点到出站组
async function processOutbounds() {
  const proxies = await fetchProxies();
  console.log(`📦 获取到 ${proxies.length} 个节点`);

  config.outbounds.forEach(outbound => {
    outboundRules.forEach(({ outboundRegex, tagRegex }) => {
      if (outboundRegex.test(outbound.tag)) {
        if (!Array.isArray(outbound.outbounds)) {
          outbound.outbounds = [];
        }
        const matchedTags = getTags(proxies, tagRegex);
        console.log(`🕳 ${outbound.tag} 匹配 ${outboundRegex}，插入 ${matchedTags.length} 个节点（🏷 ${tagRegex}）`);
        outbound.outbounds.push(...matchedTags);
      }
    });
  });

  // 处理空出站组
  const compatibleOutbound = { tag: 'COMPATIBLE', type: 'direct' };
  let hasCompatible = configOutboundTags.has('COMPATIBLE');
  config.outbounds.forEach(outbound => {
    outboundRules.forEach(({ outboundRegex }) => {
      if (outboundRegex.test(outbound.tag) && (!outbound.outbounds || outbound.outbounds.length === 0)) {
        if (!hasCompatible) {
          config.outbounds.push(compatibleOutbound);
          hasCompatible = true;
          console.log('🛡️ 创建 COMPATIBLE(direct) 出站组');
        }
        outbound.outbounds = [compatibleOutbound.tag];
        console.log(`🕳 ${outbound.tag} 出站组为空，插入 COMPATIBLE(direct)`);
      }
    });
  });

  // 将所有节点添加到配置文件
  config.outbounds.push(...proxies);
  console.log(`✅ 已将 ${proxies.length} 个节点添加到 outbounds`);
}

// 工具函数
function getTags(proxies, regex) {
  return proxies.filter(p => regex.test(p.tag)).map(p => p.tag);
}

function createRegex(pattern) {
  const isCaseInsensitive = pattern.includes('ℹ️');
  return new RegExp(pattern.replace('ℹ️', ''), isCaseInsensitive ? 'i' : undefined);
}

// 执行并输出结果
(async () => {
  try {
    await processOutbounds();
    $content = JSON.stringify(config, null, 2);
    console.log('🔚 [Sing-box 模板脚本] 执行完成');
  } catch (e) {
    console.error(`❌ 执行失败：${e.message}`);
    throw e;
  }
})();