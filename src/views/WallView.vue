<script setup>
import { t } from '../i18n'
import { computed, ref, onMounted } from 'vue'
import { supabase } from '../supabase'
import { PUBLIC_STATUSES } from '../constants'
import { errorText } from '../format'
import Icon from '../components/Icon.vue'
import QuestionCard from '../components/QuestionCard.vue'

const questions = ref([])
const tops = ref({}) // 每題「有幫助」最多的那則代答
const categories = ref([])
const loading = ref(true)
const error = ref('')

const range = ref('all') // all、waiting、answered
const cat = ref(null)
const sort = ref('new') // new、metoo
const keyword = ref('')

onMounted(async () => {
  const [qs, cs] = await Promise.all([
    supabase.from('alumni_question_feed').select('*').in('status', PUBLIC_STATUSES)
      .order('published_at', { ascending: false }).limit(500),
    supabase.from('alumni_categories').select('id, name').order('sort').order('id'),
  ])
  loading.value = false
  if (qs.error) return (error.value = errorText(qs.error))
  questions.value = qs.data
  categories.value = cs.data ?? []
  const ids = qs.data.filter((q) => q.answer_count).map((q) => q.id)
  if (!ids.length) return
  const { data } = await supabase.from('alumni_answer_feed').select('id, question_id, cohort, affiliation, alumni_name, body, helpful_count')
    .in('question_id', ids).order('helpful_count', { ascending: false }).order('created_at')
  const map = {}
  for (const a of data ?? []) map[a.question_id] ??= a
  tops.value = map
})

// 分類膠囊只列有問題的分類，加上「全部」
const usedCats = computed(() => categories.value.filter((c) => questions.value.some((q) => q.category_id === c.id)))

const shown = computed(() => {
  const k = keyword.value.trim().toLowerCase()
  const list = questions.value.filter((q) => {
    if (range.value === 'waiting' && q.status === 'answered') return false
    if (range.value === 'answered' && q.status !== 'answered') return false
    if (cat.value && q.category_id !== cat.value) return false
    if (k && !(q.title + '\n' + q.body).toLowerCase().includes(k)) return false
    return true
  })
  if (sort.value === 'metoo') return [...list].sort((a, b) => b.metoo_count - a.metoo_count)
  return list
})
</script>

<template>
  <main>
    <header class="home-head">
      <div class="brand"><img class="logo" src="/logo.svg" alt="" /><h1>{{ t('FDFZ 校友提問牆') }}</h1></div>
      <div class="vstack" style="gap:6px">
        <h2 class="wide-only">{{ t('問問走在前面的學長學姐') }}</h2>
        <p class="lede">{{ t('升學、大學生活、專業和職業，想問校友什麼都可以寫下來。校友工作部會去請教合適的校友，代為回答。') }}</p>
      </div>
      <router-link to="/ask" class="btn gold"><Icon name="ask" />{{ t('我要提問') }}</router-link>
    </header>
    <div class="page">
      <div class="seg" role="tablist" :aria-label="t('問題範圍')">
        <button type="button" role="tab" :aria-selected="range === 'all'" @click="range = 'all'">{{ t('全部') }}</button>
        <button type="button" role="tab" :aria-selected="range === 'waiting'" @click="range = 'waiting'">{{ t('等待回答') }}</button>
        <button type="button" role="tab" :aria-selected="range === 'answered'" @click="range = 'answered'">{{ t('已回答') }}</button>
      </div>
      <div v-if="usedCats.length > 1" class="chips" role="group" :aria-label="t('分類')">
        <button type="button" class="chip" :aria-pressed="!cat" @click="cat = null">{{ t('全部分類') }}</button>
        <button v-for="c in usedCats" :key="c.id" type="button" class="chip" :aria-pressed="cat === c.id" @click="cat = c.id">{{ c.name }}</button>
      </div>
      <div class="grid2">
        <label><span class="sr">{{ t('搜尋') }}</span><input v-model="keyword" type="text" :placeholder="t('搜尋問題')" /></label>
        <label><span class="sr">{{ t('排序') }}</span>
          <select v-model="sort"><option value="new">{{ t('最新公開') }}</option><option value="metoo">{{ t('最多人想問') }}</option></select>
        </label>
      </div>

      <p v-if="loading" class="empty">{{ t('載入中…') }}</p>
      <p v-else-if="error" class="error">{{ t(error) }}</p>
      <template v-else>
        <div v-if="shown.length" class="q-list"><QuestionCard v-for="q in shown" :key="q.id" :q="q" :top="tops[q.id]" /></div>
        <p v-else-if="questions.length" class="empty">{{ t('沒有符合條件的問題') }}</p>
        <div v-else class="card center">
          <p>{{ t('還沒有公開的問題。') }}</p>
          <p class="muted small">{{ t('新問題要等校友工作部看過才會公開，你問的問題可以在「我的提問」看到。') }}</p>
        </div>
      </template>
    </div>
  </main>
</template>
