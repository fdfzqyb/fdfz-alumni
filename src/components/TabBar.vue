<script setup>
import { t } from '../i18n'
import { ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { supabase } from '../supabase'
import { fixPath } from '../auth'
import Icon from './Icon.vue'

// 手機在底部、電腦在頂部（CSS 切換）
const route = useRoute()
const unread = ref(0)

// 「通知」上面的數字：未讀幾則；每次換頁重新算
async function loadUnread() {
  if (fixPath()) return (unread.value = 0)
  const { count } = await supabase.from('alumni_notifications')
    .select('id', { count: 'exact', head: true }).eq('read', false)
  unread.value = count ?? 0
}
watch(() => route.fullPath, loadUnread, { immediate: true })

const on = (...prefixes) => prefixes.some((p) => (p === '/' ? route.path === '/' : route.path.startsWith(p)))
const current = (...prefixes) => (on(...prefixes) ? 'page' : undefined)
</script>

<template>
  <nav class="tabbar" :aria-label="t('主選單')">
    <router-link class="tb-brand" to="/"><img class="logo" src="/logo.svg" alt="" />{{ t('FDFZ 校友提問牆') }}</router-link>
    <router-link to="/" :aria-current="route.path === '/' || /^\/q\/\d+$/.test(route.path) ? 'page' : undefined"><Icon name="chat" :size="24" />{{ t('問題牆') }}</router-link>
    <router-link to="/ask" class="tb-ask" :aria-current="current('/ask')"><Icon name="ask" :size="24" />{{ t('提問') }}</router-link>
    <router-link to="/mine" :aria-current="current('/mine')"><Icon name="hand" :size="24" />{{ t('我的提問') }}</router-link>
    <router-link to="/notifications" :aria-current="current('/notifications')">
      <Icon name="bell" :size="24" />{{ t('通知') }}<span v-if="unread" class="badge">{{ unread }}</span>
    </router-link>
    <router-link to="/account" :aria-current="current('/account', '/admin')"><Icon name="user" :size="24" />{{ t('帳號') }}</router-link>
  </nav>
</template>
