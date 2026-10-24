<script setup>
import { t } from '../i18n'
import { computed, ref, onMounted } from 'vue'
import { supabase } from '../supabase'
import { errorText } from '../format'
import Icon from '../components/Icon.vue'
import QuestionCard from '../components/QuestionCard.vue'

// 我問過的所有問題，包括還沒公開和暫無法回答的
const questions = ref([])
const loading = ref(true)
const error = ref('')

onMounted(async () => {
  const { data, error: e } = await supabase.from('alumni_question_feed').select('*').eq('is_mine', true)
    .order('created_at', { ascending: false })
  loading.value = false
  if (e) return (error.value = errorText(e))
  questions.value = data
})

const hiddenCount = computed(() => questions.value.filter((q) => q.status === 'hidden').length)
</script>

<template>
  <main>
    <header class="topbar"><h1>{{ t('我的提問') }}</h1></header>
    <div class="page">
      <h1 class="page-title">{{ t('我的提問') }}</h1>
      <p v-if="loading" class="empty">{{ t('載入中…') }}</p>
      <p v-else-if="error" class="error">{{ t(error) }}</p>
      <template v-else>
        <div v-if="hiddenCount" class="note gold"><Icon name="clock" :size="20" />
          <span>{{ t('有 {n} 個問題還沒公開，校友工作部看過後才會讓其他同學看到。', { n: hiddenCount }) }}</span></div>
        <div v-if="questions.length" class="q-list"><QuestionCard v-for="q in questions" :key="q.id" :q="q" /></div>
        <div v-else class="card center">
          <p>{{ t('你還沒有提問。') }}</p>
          <router-link to="/ask" class="btn gold"><Icon name="ask" />{{ t('我要提問') }}</router-link>
        </div>
      </template>
    </div>
  </main>
</template>
