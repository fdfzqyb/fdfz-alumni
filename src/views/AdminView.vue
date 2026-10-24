<script setup>
import { t } from '../i18n'
import { computed, ref, onMounted } from 'vue'
import { supabase } from '../supabase'
import { STATUSES } from '../constants'
import { stamp, errorText } from '../format'
import { toast } from '../toast'
import Icon from '../components/Icon.vue'
import Modal from '../components/Modal.vue'
import StatusTag from '../components/StatusTag.vue'
import QuestionCard from '../components/QuestionCard.vue'

// 校友工作部後台：待公開、全部問題、修改刪除申請、分類、成員
const tab = ref('hidden')
const questions = ref([])
const requests = ref([])
const categories = ref([])
const staff = ref([])
const loading = ref(true)

async function loadQuestions() {
  const { data } = await supabase.from('alumni_question_feed').select('*').order('created_at', { ascending: false }).limit(1000)
  questions.value = data ?? []
}
async function loadRequests() {
  const { data } = await supabase.from('alumni_change_requests').select('*').eq('status', 'pending').order('created_at')
  requests.value = data ?? []
}
async function loadCategories() {
  const { data } = await supabase.from('alumni_categories').select('*').order('sort').order('id')
  categories.value = (data ?? []).map((c) => ({ ...c, draft: { name: c.name, sort: c.sort, active: c.active } }))
}
async function loadStaffList() {
  const { data } = await supabase.rpc('alumni_staff_list')
  staff.value = data ?? []
}

onMounted(async () => {
  await Promise.all([loadQuestions(), loadRequests(), loadCategories(), loadStaffList()])
  loading.value = false
})

const hidden = computed(() => questions.value.filter((q) => q.status === 'hidden').reverse()) // 先問的先處理
const qById = computed(() => Object.fromEntries(questions.value.map((q) => [q.id, q])))
const catName = (id) => categories.value.find((c) => c.id === id)?.name ?? ''

// 待公開：直接在列表上公開或標成暫無法回答
const unableFor = ref(null)
const unableNote = ref('')
async function setStatus(q, status, note = null) {
  const { error } = await supabase.rpc('alumni_set_status', { p_id: q.id, p_status: status, p_note: note })
  if (error) return toast(errorText(error))
  toast(status === 'unable' ? '已標為暫無法回答' : '已公開')
  unableFor.value = null
  await loadQuestions()
}

// 全部問題：按狀態篩
const statusFilter = ref('')
const filtered = computed(() => questions.value.filter((q) => !statusFilter.value || q.status === statusFilter.value))
const countOf = (s) => questions.value.filter((q) => q.status === s).length

// 修改刪除申請
const rejectFor = ref(null)
const rejectReason = ref('')
async function review(r, approve, reason = null) {
  const { error } = await supabase.rpc('alumni_review_request', { p_id: r.id, p_approve: approve, p_reason: reason })
  if (error) return toast(errorText(error))
  toast(approve ? '已同意' : '已退回')
  rejectFor.value = null
  rejectReason.value = ''
  await Promise.all([loadRequests(), loadQuestions()])
}

// 分類
const newCat = ref('')
async function saveCat(c) {
  const d = c.draft
  const { error } = await supabase.rpc('alumni_save_category', { p_id: c.id, p_name: d.name, p_sort: Number(d.sort) || 0, p_active: d.active })
  if (error) return toast(errorText(error))
  toast('已儲存')
  loadCategories()
}
async function addCat() {
  const { error } = await supabase.rpc('alumni_save_category', { p_id: null, p_name: newCat.value, p_sort: (categories.value.at(-1)?.sort ?? 0) + 1 })
  if (error) return toast(errorText(error))
  newCat.value = ''
  loadCategories()
}
const dirty = (c) => c.draft.name !== c.name || Number(c.draft.sort) !== c.sort || c.draft.active !== c.active

// 成員
const newSid = ref('')
async function addStaff() {
  const { error } = await supabase.rpc('alumni_add_staff', { p_student_id: newSid.value })
  if (error) return toast(errorText(error))
  newSid.value = ''
  toast('已加入')
  loadStaffList()
}
const removingStaff = ref(null)
async function removeStaff() {
  const { error } = await supabase.rpc('alumni_remove_staff', { p_user: removingStaff.value.user_id })
  removingStaff.value = null
  if (error) return toast(errorText(error))
  loadStaffList()
}

const TABS = [['hidden', '待公開'], ['all', '全部問題'], ['requests', '修改刪除申請'], ['categories', '分類'], ['staff', '成員']]
const badge = (k) => (k === 'hidden' ? hidden.value.length : k === 'requests' ? requests.value.length : 0)
</script>

<template>
  <main>
    <header class="topbar">
      <router-link class="back" to="/account" :aria-label="t('返回')"><Icon name="back" /></router-link>
      <h1>{{ t('校友工作部後台') }}</h1>
    </header>
    <div class="page">
      <h1 class="page-title">{{ t('校友工作部後台') }}</h1>
      <div class="chips" role="tablist">
        <button v-for="[k, label] in TABS" :key="k" type="button" role="tab" class="chip" :aria-pressed="tab === k" @click="tab = k">
          {{ t(label) }}<template v-if="badge(k)"> {{ badge(k) }}</template>
        </button>
      </div>
      <p v-if="loading" class="empty">{{ t('載入中…') }}</p>

      <template v-else-if="tab === 'hidden'">
        <p class="muted small">{{ t('新問題先在這裡。看過沒問題就公開，不適合公開的標成「暫無法回答」，只有提問者看得到。') }}</p>
        <article v-for="q in hidden" :key="q.id" class="card">
          <div class="hstack"><StatusTag :status="q.status" /><span class="tag">{{ q.category_name }}</span>
            <span class="muted tiny">{{ q.author_name }} · {{ q.author_student_id }}<template v-if="q.anonymous"> · {{ t('匿名提問') }}</template> · {{ stamp(q.created_at) }}</span></div>
          <h3>{{ q.title }}</h3>
          <p class="pre small">{{ q.body }}</p>
          <p v-if="q.wish" class="small"><span class="muted">{{ t('希望回答的校友：') }}</span>{{ q.wish }}</p>
          <div class="actions">
            <button class="btn small" type="button" @click="setStatus(q, 'open')"><Icon name="check" :size="18" />{{ t('公開（待回答）') }}</button>
            <button class="btn plain small" type="button" @click="setStatus(q, 'contacting')">{{ t('公開（聯繫校友中）') }}</button>
            <button class="btn danger small" type="button" @click="unableFor = q; unableNote = ''">{{ t('暫無法回答') }}</button>
            <router-link class="btn plain small" :to="`/q/${q.id}`">{{ t('打開') }}</router-link>
          </div>
        </article>
        <p v-if="!hidden.length" class="empty">{{ t('沒有待公開的問題') }}</p>
      </template>

      <template v-else-if="tab === 'all'">
        <div class="chips">
          <button type="button" class="chip" :aria-pressed="!statusFilter" @click="statusFilter = ''">{{ t('全部') }} {{ questions.length }}</button>
          <button v-for="s in STATUSES" :key="s.key" type="button" class="chip" :aria-pressed="statusFilter === s.key" @click="statusFilter = s.key">{{ t(s.label) }} {{ countOf(s.key) }}</button>
        </div>
        <div v-if="filtered.length" class="q-list"><QuestionCard v-for="q in filtered" :key="q.id" :q="q" show-author /></div>
        <p v-else class="empty">{{ t('沒有問題') }}</p>
      </template>

      <template v-else-if="tab === 'requests'">
        <p class="muted small">{{ t('問題已有校友回答後，提問者要修改或刪除，需要任一位校友工作部成員同意。') }}</p>
        <article v-for="r in requests" :key="r.id" class="card">
          <div class="row">
            <b>{{ r.kind === 'edit' ? t('修改申請') : t('刪除申請') }}</b>
            <span class="muted tiny">{{ qById[r.question_id]?.author_name }} · {{ qById[r.question_id]?.author_student_id }} · {{ stamp(r.created_at) }}</span>
          </div>
          <p v-if="r.reason" class="small"><span class="muted">{{ t('原因：') }}</span>{{ r.reason }}</p>
          <div class="vstack" style="gap:6px">
            <span class="field-t">{{ t('現在') }}</span>
            <div class="idbox">
              <dt>{{ t('分類') }}</dt><dd>{{ qById[r.question_id]?.category_name }}</dd>
              <dt>{{ t('標題') }}</dt><dd>{{ qById[r.question_id]?.title }}</dd>
              <dt>{{ t('內容') }}</dt><dd class="pre" style="font-weight:400">{{ qById[r.question_id]?.body }}</dd>
            </div>
          </div>
          <div v-if="r.kind === 'edit'" class="vstack" style="gap:6px">
            <span class="field-t">{{ t('改成') }}</span>
            <div class="idbox">
              <dt>{{ t('分類') }}</dt><dd>{{ catName(r.new_category_id) }}</dd>
              <dt>{{ t('標題') }}</dt><dd>{{ r.new_title }}</dd>
              <dt>{{ t('內容') }}</dt><dd class="pre" style="font-weight:400">{{ r.new_body }}</dd>
              <dt>{{ t('希望回答') }}</dt><dd>{{ r.new_wish || '—' }}</dd>
              <dt>{{ t('匿名') }}</dt><dd>{{ r.new_anonymous ? t('是') : t('否') }}</dd>
            </div>
          </div>
          <div class="actions">
            <button class="btn small" type="button" @click="review(r, true)">{{ t('同意') }}</button>
            <button class="btn plain small" type="button" @click="rejectFor = r; rejectReason = ''">{{ t('退回') }}</button>
            <router-link class="btn plain small" :to="`/q/${r.question_id}`">{{ t('打開問題') }}</router-link>
          </div>
        </article>
        <p v-if="!requests.length" class="empty">{{ t('沒有待處理的申請') }}</p>
      </template>

      <template v-else-if="tab === 'categories'">
        <p class="muted small">{{ t('排序數字小的排前面。停用的分類不能再選，舊問題保留原分類。') }}</p>
        <div class="card">
          <table class="tbl">
            <thead><tr><th>{{ t('名稱') }}</th><th style="width:76px">{{ t('排序') }}</th><th style="width:60px">{{ t('啟用') }}</th><th style="width:72px"></th></tr></thead>
            <tbody>
              <tr v-for="c in categories" :key="c.id">
                <td><input v-model="c.draft.name" type="text" maxlength="20" /></td>
                <td><input v-model="c.draft.sort" type="number" /></td>
                <td><input v-model="c.draft.active" type="checkbox" style="width:20px;height:20px;accent-color:var(--primary)" /></td>
                <td><button class="btn small" type="button" :disabled="!dirty(c)" @click="saveCat(c)">{{ t('儲存') }}</button></td>
              </tr>
            </tbody>
          </table>
          <div class="hstack" style="flex-wrap:nowrap">
            <input v-model="newCat" type="text" maxlength="20" :placeholder="t('新分類名稱')" />
            <button class="btn" type="button" @click="addCat"><Icon name="plus" :size="18" />{{ t('新增') }}</button>
          </div>
        </div>
      </template>

      <template v-else-if="tab === 'staff'">
        <p class="muted small">{{ t('成員可以公開問題、代答、處理申請、管理分類和成員。對方要先在帳號中心註冊並通過校園卡審核。') }}</p>
        <div class="card">
          <div class="list">
            <div v-for="s in staff" :key="s.user_id" class="row">
              <span><b>{{ s.full_name }}</b> <span class="muted small">{{ s.student_id }}</span></span>
              <button class="btn plain small" type="button" @click="removingStaff = s">{{ t('移除') }}</button>
            </div>
          </div>
          <div class="hstack" style="flex-wrap:nowrap">
            <input v-model="newSid" type="text" inputmode="numeric" maxlength="8" :placeholder="t('八位學號')" />
            <button class="btn" type="button" @click="addStaff"><Icon name="plus" :size="18" />{{ t('加入') }}</button>
          </div>
        </div>
      </template>
    </div>

    <Modal :open="!!unableFor" :title="t('標成「暫無法回答」')" @update:open="unableFor = null">
      <p class="small">{{ t('只有提問者和校友工作部看得到這個問題。提問者會收到通知。') }}</p>
      <label class="field"><span>{{ t('原因') }}</span><input v-model="unableNote" type="text" maxlength="200" :placeholder="t('選填，提問者會看到')" /></label>
      <div class="actions">
        <button class="btn" type="button" @click="setStatus(unableFor, 'unable', unableNote)">{{ t('確定') }}</button>
        <button class="btn plain" type="button" @click="unableFor = null">{{ t('取消') }}</button>
      </div>
    </Modal>

    <Modal :open="!!rejectFor" :title="t('退回申請')" @update:open="rejectFor = null">
      <label class="field"><span>{{ t('退回原因') }}</span><input v-model="rejectReason" type="text" maxlength="200" :placeholder="t('選填，提問者會看到')" /></label>
      <div class="actions">
        <button class="btn" type="button" @click="review(rejectFor, false, rejectReason)">{{ t('退回') }}</button>
        <button class="btn plain" type="button" @click="rejectFor = null">{{ t('取消') }}</button>
      </div>
    </Modal>

    <Modal :open="!!removingStaff" :title="t('移除成員')" @update:open="removingStaff = null">
      <p>{{ t('確定把 {name} 移出校友工作部？', { name: removingStaff?.full_name }) }}</p>
      <div class="actions">
        <button class="btn" type="button" style="background:var(--danger);border-color:var(--danger)" @click="removeStaff">{{ t('移除') }}</button>
        <button class="btn plain" type="button" @click="removingStaff = null">{{ t('取消') }}</button>
      </div>
    </Modal>
  </main>
</template>
