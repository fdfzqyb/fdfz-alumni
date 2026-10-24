<script setup>
import { t } from '../i18n'
import { ref } from 'vue'
import { supabase } from '../supabase'
import { errorText } from '../format'

// 校友工作部貼代答或改代答。answer 有值時是修改
const props = defineProps({ questionId: { type: Number, required: true }, answer: Object })
const emit = defineEmits(['saved', 'cancel'])

const a = props.answer
const form = ref({
  cohort: a?.cohort ?? '',
  affiliation: a?.affiliation ?? '',
  alumni_name: a?.alumni_name ?? '',
  body: a?.body ?? '',
})
const busy = ref(false)
const error = ref('')

async function save() {
  const f = form.value
  if (!String(f.cohort).trim()) return (error.value = '請填校友的屆別（畢業年份，例如 2019）')
  if (!f.affiliation.trim()) return (error.value = '請填校友的大學或工作單位')
  if (!f.body.trim()) return (error.value = '請填回答內容')
  busy.value = true
  error.value = ''
  const { error: e } = await supabase.rpc('alumni_save_answer', { p_question: props.questionId, p_id: a?.id ?? null, p: f })
  busy.value = false
  if (e) return (error.value = errorText(e))
  if (!a) form.value = { cohort: '', affiliation: '', alumni_name: '', body: '' }
  emit('saved')
}
</script>

<template>
  <div class="vstack">
    <div class="grid2">
      <label class="field"><span>{{ t('屆別（畢業年份）') }}<span class="req">*</span></span>
        <input v-model="form.cohort" type="number" inputmode="numeric" min="1950" max="2100" :placeholder="t('例如 2019')" />
      </label>
      <label class="field"><span>{{ t('大學或工作單位') }}<span class="req">*</span></span>
        <input v-model="form.affiliation" type="text" maxlength="60" :placeholder="t('例如：某某大學')" />
      </label>
    </div>
    <label class="field"><span>{{ t('校友姓名') }}</span>
      <input v-model="form.alumni_name" type="text" maxlength="30" :placeholder="t('選填，校友同意才寫')" />
    </label>
    <label class="field"><span>{{ t('回答內容') }}<span class="req">*</span></span>
      <textarea v-model="form.body" maxlength="5000" :placeholder="t('整理校友的回答')" />
    </label>
    <p v-if="error" class="error">{{ t(error) }}</p>
    <div class="actions">
      <button class="btn" type="button" :disabled="busy" @click="save">{{ a ? t('儲存修改') : t('發布代答') }}</button>
      <button v-if="a" class="btn plain" type="button" @click="emit('cancel')">{{ t('取消') }}</button>
    </div>
    <p v-if="!a" class="muted tiny">{{ t('發布後問題會變成「已回答」，並通知提問者。') }}</p>
  </div>
</template>
