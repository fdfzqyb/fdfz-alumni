<script setup>
import { t } from '../i18n'
import { computed, ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../supabase'
import { errorText } from '../format'
import { toast } from '../toast'
import Icon from '../components/Icon.vue'

// /ask 提問；/q/:id/edit 修改自己的問題（已有代答時變成送出申請）
const route = useRoute()
const router = useRouter()
const editId = route.params.id ? Number(route.params.id) : null

const categories = ref([])
const form = ref({ category_id: null, title: '', body: '', wish: '', anonymous: true, reason: '' })
const original = ref(null)
const loading = ref(true)
const busy = ref(false)
const error = ref('')

onMounted(async () => {
  const [cs, q] = await Promise.all([
    supabase.from('alumni_categories').select('id, name').eq('active', true).order('sort').order('id'),
    editId ? supabase.from('alumni_question_feed').select('*').eq('id', editId).maybeSingle() : { data: null },
  ])
  categories.value = cs.data ?? []
  if (editId) {
    if (!q.data?.is_mine) return router.replace('/mine')
    original.value = q.data
    const { category_id, title, body, wish, anonymous } = q.data
    form.value = { category_id, title, body, wish, anonymous, reason: '' }
  }
  // 停用的分類不能再選；只有一個分類時直接選好
  if (!categories.value.some((c) => c.id === form.value.category_id)) form.value.category_id = null
  if (categories.value.length === 1) form.value.category_id = categories.value[0].id
  loading.value = false
})

const needsApproval = computed(() => original.value && original.value.answer_count > 0)

async function submit() {
  const f = form.value
  // 不用「沒填就停用按鈕」：iPhone 中文輸入法還在選字時，欄位看起來有字、程式卻還收不到
  if (!f.category_id) return (error.value = '請選分類')
  if (!f.title.trim()) return (error.value = '請填標題')
  if (!f.body.trim()) return (error.value = '請填問題內容')
  busy.value = true
  error.value = ''
  if (!editId) {
    const { data, error: e } = await supabase.rpc('alumni_ask', { p: f })
    busy.value = false
    if (e) return (error.value = errorText(e))
    toast('已送出，校友工作部看過後會公開')
    return router.replace(`/q/${data}`)
  }
  const { data, error: e } = await supabase.rpc('alumni_change_my_question', { p_id: editId, p_kind: 'edit', p: f })
  busy.value = false
  if (e) return (error.value = errorText(e))
  toast(data === 'done' ? '已修改' : '已送出修改申請，校友工作部同意後生效')
  router.replace(`/q/${editId}`)
}
</script>

<template>
  <main>
    <header class="topbar">
      <button class="back" type="button" :aria-label="t('返回')" @click="router.back()"><Icon name="back" /></button>
      <h1>{{ editId ? t('修改問題') : t('向校友提問') }}</h1>
    </header>
    <div class="page narrow">
      <h1 class="page-title">{{ editId ? t('修改問題') : t('向校友提問') }}</h1>
      <p v-if="loading" class="empty">{{ t('載入中…') }}</p>
      <template v-else>
        <div v-if="!editId" class="note gold"><Icon name="cap" :size="20" />
          <span>{{ t('問題送出後先是「未公開」，校友工作部看過後才會讓其他同學看到，再去請教合適的校友代為回答。') }}</span>
        </div>
        <div v-if="needsApproval" class="note warn"><Icon name="warn" :size="20" />
          <span>{{ t('這個問題已經有校友回答，修改要等校友工作部同意後才會生效。') }}</span>
        </div>
        <form class="card" @submit.prevent="submit">
          <fieldset>
            <legend class="field-t">{{ t('分類') }}<span class="req">*</span></legend>
            <div class="chips">
              <button v-for="c in categories" :key="c.id" type="button" class="chip" :aria-pressed="form.category_id === c.id" @click="form.category_id = c.id">{{ c.name }}</button>
            </div>
          </fieldset>
          <label class="field"><span>{{ t('標題') }}<span class="req">*</span></span>
            <input v-model="form.title" type="text" maxlength="60" :placeholder="t('一句話說清楚想問什麼')" />
          </label>
          <label class="field"><span>{{ t('問題內容') }}<span class="req">*</span></span>
            <textarea v-model="form.body" maxlength="3000" :placeholder="t('你的情況、已經知道什麼、具體想知道什麼')" />
          </label>
          <label class="field"><span>{{ t('希望哪類校友回答') }}</span>
            <input v-model="form.wish" type="text" maxlength="60" :placeholder="t('選填，例如：讀醫學的、在國外讀本科的')" />
            <small>{{ t('方便校友工作部找合適的人') }}</small>
          </label>
          <label class="check"><input v-model="form.anonymous" type="checkbox" />
            <span>{{ t('匿名提問') }}<small>{{ t('其他同學看不到是誰問的；校友工作部仍看得到。') }}</small></span>
          </label>
          <label v-if="needsApproval" class="field"><span>{{ t('修改原因') }}</span>
            <input v-model="form.reason" type="text" maxlength="200" :placeholder="t('選填，給校友工作部看')" />
          </label>
          <p v-if="error" class="error">{{ t(error) }}</p>
          <button class="btn block" type="submit" :disabled="busy">
            {{ !editId ? t('送出問題') : needsApproval ? t('送出修改申請') : t('儲存修改') }}
          </button>
        </form>
      </template>
    </div>
  </main>
</template>
