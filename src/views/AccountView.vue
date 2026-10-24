<script setup>
import { locale, setLocale, t } from '../i18n'
import { computed, ref, onMounted } from 'vue'
import { supabase } from '../supabase'
import { auth, signOut, loadStaff } from '../auth'
import { accountUrl } from '../fdfz'
import Icon from '../components/Icon.vue'

const profile = computed(() => auth.profile ?? {})
const todo = ref({ hidden: 0, requests: 0 })

onMounted(async () => {
  await loadStaff()
  if (!auth.isStaff) return
  const [h, r] = await Promise.all([
    supabase.from('alumni_questions').select('id', { count: 'exact', head: true }).eq('status', 'hidden'),
    supabase.from('alumni_change_requests').select('id', { count: 'exact', head: true }).eq('status', 'pending'),
  ])
  todo.value = { hidden: h.count ?? 0, requests: r.count ?? 0 }
})

async function logout() {
  await signOut()
  window.location.assign(accountUrl('/login', location.origin + '/'))
}
</script>

<template>
  <main>
    <header class="topbar"><h1>{{ t('帳號') }}</h1></header>
    <div class="page narrow">
      <h1 class="page-title">{{ t('帳號') }}</h1>
      <div class="card">
        <div class="person">
          <span class="av">{{ Array.from(profile.full_name ?? '?')[0] }}</span>
          <span style="flex:1"><b style="font-size:18px">{{ profile.full_name }}</b><br /><span class="muted small">{{ t('學號 {sid}', { sid: profile.student_id }) }}</span></span>
          <span class="status st-answered"><Icon name="check" :size="14" />{{ t('校園卡已驗證') }}</span>
        </div>
      </div>

      <router-link v-if="auth.isStaff" class="card entry" to="/admin">
        <span class="icon-tile"><Icon name="shield" /></span>
        <span class="grow"><b>{{ t('校友工作部後台') }}</b><br />
          <span class="muted small">{{ t('{a} 個問題待公開 · {b} 份修改刪除申請', { a: todo.hidden, b: todo.requests }) }}</span></span>
        <Icon name="go" class="go" :size="18" />
      </router-link>

      <section class="card" aria-labelledby="language-heading">
        <h3 id="language-heading">{{ t('語言') }}</h3>
        <div class="grid2" role="group" aria-labelledby="language-heading">
          <button type="button" class="btn" :class="{ ghost: locale !== 'zh-Hans' }" :aria-pressed="locale === 'zh-Hans'" lang="zh-Hans" @click="setLocale('zh-Hans')">简体中文</button>
          <button type="button" class="btn" :class="{ ghost: locale !== 'zh-Hant' }" :aria-pressed="locale === 'zh-Hant'" lang="zh-Hant" @click="setLocale('zh-Hant')">繁體中文</button>
        </div>
      </section>
      <a :href="accountUrl('/')" class="btn plain block">{{ t('帳號設定（改密碼）') }}</a>
      <button class="btn plain block" type="button" @click="logout">{{ t('登出') }}</button>
      <p class="muted tiny center">{{ t('帳號和 FDFZ 權益牆、樹洞、社團活動共用，在任何一站登入或登出都會同步。') }}</p>
    </div>
  </main>
</template>
