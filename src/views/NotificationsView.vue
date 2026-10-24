<script setup>
import { t } from '../i18n'
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../supabase'
import { stamp } from '../format'

const router = useRouter()
const items = ref([])
const loading = ref(true)

async function load() {
  const { data } = await supabase.from('alumni_notifications').select('*')
    .order('created_at', { ascending: false }).limit(100)
  items.value = data ?? []
  loading.value = false
}
onMounted(load)

// 通知文字由資料庫產生（繁體），格式是「固定文字「問題標題」固定文字。原因：同學寫的原因」。
// 只翻固定的部分，標題和原因照原文
function show(msg) {
  const a = msg.indexOf('「')
  const b = msg.lastIndexOf('」')
  if (a < 0 || b < a) return t(msg)
  const [rest, ...reason] = msg.slice(b + 1).split('。原因：')
  return t(msg.slice(0, a)) + msg.slice(a, b + 1) + t(rest) + (reason.length ? t('。原因：') + reason.join('。原因：') : '')
}

async function open(n) {
  if (!n.read) {
    await supabase.rpc('alumni_mark_read', { p_id: n.id })
    n.read = true
  }
  if (n.question_id) router.push(`/q/${n.question_id}`)
}

async function readAll() {
  await supabase.rpc('alumni_mark_read')
  items.value.forEach((n) => (n.read = true))
}
</script>

<template>
  <main>
    <header class="topbar"><h1>{{ t('通知') }}</h1></header>
    <div class="page narrow">
      <div class="row">
        <h1 class="page-title">{{ t('通知') }}</h1>
        <button v-if="items.some((n) => !n.read)" class="btn plain small" type="button" style="margin-left:auto" @click="readAll">{{ t('全部標為已讀') }}</button>
      </div>
      <p v-if="loading" class="empty">{{ t('載入中…') }}</p>
      <div v-else-if="items.length" class="card">
        <div class="list">
          <button v-for="n in items" :key="n.id" type="button" class="notice" :class="{ read: n.read }" @click="open(n)">
            <span class="dot" />
            <span style="flex:1"><span>{{ show(n.message) }}</span><br /><span class="muted tiny">{{ stamp(n.created_at) }}</span></span>
          </button>
        </div>
      </div>
      <p v-else class="empty">{{ t('還沒有通知。問題公開、狀態改變、有校友回答時，會在這裡告訴你。') }}</p>
    </div>
  </main>
</template>
