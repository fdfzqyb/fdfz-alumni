<script setup>
import { t } from '../i18n'
import { computed, ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../supabase'
import { isStaff, myId } from '../auth'
import { STATUSES, PUBLIC_STATUSES, alumniLabel } from '../constants'
import { stamp, errorText } from '../format'
import { toast } from '../toast'
import Icon from '../components/Icon.vue'
import Modal from '../components/Modal.vue'
import StatusTag from '../components/StatusTag.vue'
import AnswerForm from '../components/AnswerForm.vue'

const route = useRoute()
const router = useRouter()
const id = Number(route.params.id)

const q = ref(null)
const answers = ref([])
const request = ref(null) // 自己待處理的修改刪除申請
const loading = ref(true)

async function load() {
  const [qs, as] = await Promise.all([
    supabase.from('alumni_question_feed').select('*').eq('id', id).maybeSingle(),
    supabase.from('alumni_answer_feed').select('*').eq('question_id', id)
      .order('helpful_count', { ascending: false }).order('created_at'),
  ])
  q.value = qs.data
  answers.value = as.data ?? []
  if (q.value?.is_mine && q.value.pending_request) {
    const { data } = await supabase.from('alumni_change_requests').select('id, kind, created_at')
      .eq('question_id', id).eq('requester', myId()).eq('status', 'pending').maybeSingle()
    request.value = data
  } else request.value = null
  loading.value = false
}
onMounted(load)

const isPublic = computed(() => q.value && PUBLIC_STATUSES.includes(q.value.status))

async function toggleMetoo() {
  const { data, error } = await supabase.rpc('alumni_toggle_metoo', { p_id: id })
  if (error) return toast(errorText(error))
  q.value.metoo_mine = data
  q.value.metoo_count += data ? 1 : -1
}

async function toggleHelpful(a) {
  const { data, error } = await supabase.rpc('alumni_toggle_helpful', { p_id: a.id })
  if (error) return toast(errorText(error))
  a.helpful_mine = data
  a.helpful_count += data ? 1 : -1
}

// 提問者刪除：沒有代答直接刪，有代答送申請
const delOpen = ref(false)
const delReason = ref('')
async function deleteMine() {
  const { data, error } = await supabase.rpc('alumni_change_my_question', { p_id: id, p_kind: 'delete', p: { reason: delReason.value } })
  delOpen.value = false
  if (error) return toast(errorText(error))
  if (data === 'done') {
    toast('已刪除')
    return router.replace('/mine')
  }
  toast('已送出刪除申請，校友工作部同意後生效')
  load()
}

async function withdraw() {
  const { error } = await supabase.rpc('alumni_withdraw_request', { p_id: request.value.id })
  if (error) return toast(errorText(error))
  toast('已撤回申請')
  load()
}

// 校友工作部：改狀態
const statusOpen = ref(false)
const nextStatus = ref('')
const note = ref('')
function pickStatus(s) {
  nextStatus.value = s
  note.value = s === q.value.status ? q.value.status_note ?? '' : ''
  statusOpen.value = true
}
async function saveStatus() {
  const { error } = await supabase.rpc('alumni_set_status', { p_id: id, p_status: nextStatus.value, p_note: note.value })
  statusOpen.value = false
  if (error) return toast(errorText(error))
  toast('已更新狀態，提問者會收到通知')
  load()
}

// 校友工作部：改、刪代答
const editing = ref(null)
const removing = ref(null)
async function removeAnswer() {
  const { error } = await supabase.rpc('alumni_delete_answer', { p_id: removing.value.id })
  removing.value = null
  if (error) return toast(errorText(error))
  load()
}
function answerSaved() {
  editing.value = null
  toast('已儲存')
  load()
}

// 校友工作部：直接刪問題
const staffDelOpen = ref(false)
const staffDelReason = ref('')
async function staffDelete() {
  const { error } = await supabase.rpc('alumni_staff_delete_question', { p_id: id, p_reason: staffDelReason.value })
  staffDelOpen.value = false
  if (error) return toast(errorText(error))
  toast('已刪除，提問者會收到通知')
  router.replace('/admin')
}
</script>

<template>
  <main>
    <header class="topbar">
      <button class="back" type="button" :aria-label="t('返回')" @click="router.back()"><Icon name="back" /></button>
      <h1>{{ t('問題') }}</h1>
    </header>
    <div class="page narrow">
      <p v-if="loading" class="empty">{{ t('載入中…') }}</p>
      <div v-else-if="!q" class="card center">
        <p>{{ t('找不到這個問題。') }}</p>
        <p class="muted small">{{ t('可能已經刪除，或者還沒有公開。') }}</p>
        <router-link to="/" class="btn plain">{{ t('回到問題牆') }}</router-link>
      </div>
      <template v-else>
        <article class="card">
          <div class="hstack"><StatusTag :status="q.status" /><span class="tag">{{ q.category_name }}</span></div>
          <h1 style="font-size:22px">{{ q.title }}</h1>
          <p class="pre">{{ q.body }}</p>
          <p v-if="q.wish" class="small"><span class="muted">{{ t('希望回答的校友：') }}</span>{{ q.wish }}</p>
          <div class="q-foot">
            <span>{{ q.author_name ? q.author_name : t('匿名同學') }}<template v-if="q.author_student_id"> · {{ q.author_student_id }}</template><template v-if="q.anonymous && q.author_name"> · {{ t('匿名提問') }}</template></span>
            <span>{{ t('{d} 提問', { d: stamp(q.created_at) }) }}</span>
            <span v-if="q.edited_at">{{ t('{d} 修改過', { d: stamp(q.edited_at) }) }}</span>
          </div>
          <div class="hstack">
            <button v-if="!q.is_mine && isPublic" class="toggle" type="button" :aria-pressed="q.metoo_mine" @click="toggleMetoo">
              <Icon name="hand" :size="18" />{{ t('我也想問') }} {{ q.metoo_count }}
            </button>
            <span v-else class="muted small"><Icon name="hand" :size="18" /> {{ t('{n} 人也想問', { n: q.metoo_count }) }}</span>
          </div>
        </article>

        <template v-if="q.is_mine">
          <div v-if="q.status === 'hidden'" class="note gold"><Icon name="clock" :size="20" />
            <span>{{ t('還沒公開，等校友工作部看過後才會讓其他同學看到。') }}</span></div>
          <div v-if="q.status === 'unable'" class="note warn"><Icon name="warn" :size="20" />
            <span><b>{{ t('校友工作部暫時無法回答這個問題，其他同學看不到它。') }}</b><template v-if="q.status_note">{{ t('原因：{r}', { r: q.status_note }) }}</template></span></div>
          <div v-if="request" class="note"><Icon name="clock" :size="20" />
            <span style="flex:1">{{ request.kind === 'edit' ? t('你的修改申請正在等校友工作部處理。') : t('你的刪除申請正在等校友工作部處理。') }}</span>
            <button class="btn plain small" type="button" @click="withdraw">{{ t('撤回') }}</button>
          </div>
          <div v-else class="actions">
            <router-link :to="`/q/${id}/edit`" class="btn plain small"><Icon name="edit" :size="18" />{{ t('修改') }}</router-link>
            <button class="btn danger small" type="button" @click="delOpen = true">{{ t('刪除') }}</button>
            <span v-if="q.answer_count" class="muted tiny" style="align-self:center">{{ t('已有校友回答，修改和刪除要校友工作部同意') }}</span>
          </div>
        </template>

        <h2 class="sec-t">{{ answers.length ? t('校友回答（{n}）', { n: answers.length }) : t('校友回答') }}</h2>
        <p v-if="!answers.length" class="muted small">{{ q.status === 'contacting' ? t('校友工作部正在聯繫校友。') : t('還沒有校友回答。') }}</p>
        <div v-for="a in answers" :key="a.id" class="answer">
          <template v-if="editing?.id === a.id">
            <AnswerForm :question-id="id" :answer="a" @saved="answerSaved" @cancel="editing = null" />
          </template>
          <template v-else>
            <span class="who"><Icon name="cap" />{{ alumniLabel(a, t) }}</span>
            <p class="pre">{{ a.body }}</p>
            <div class="row">
              <button class="toggle" type="button" :aria-pressed="a.helpful_mine" @click="toggleHelpful(a)">
                <Icon name="thumb" :size="18" />{{ t('有幫助') }} {{ a.helpful_count }}
              </button>
              <span class="muted tiny">{{ t('校友工作部代答') }} · {{ stamp(a.created_at) }}<template v-if="a.poster_name"> · {{ a.poster_name }}</template></span>
            </div>
            <div v-if="isStaff()" class="actions">
              <button class="btn plain small" type="button" @click="editing = a">{{ t('修改') }}</button>
              <button class="btn danger small" type="button" @click="removing = a">{{ t('刪除') }}</button>
            </div>
          </template>
        </div>

        <section v-if="isStaff()" class="card staff-box">
          <h3><Icon name="shield" />{{ t('校友工作部') }}</h3>
          <div class="vstack" style="gap:6px">
            <span class="field-t">{{ t('狀態') }}</span>
            <div class="chips">
              <button v-for="s in STATUSES" :key="s.key" type="button" class="chip" :aria-pressed="q.status === s.key" @click="pickStatus(s.key)">{{ t(s.label) }}</button>
            </div>
            <p v-if="q.status === 'unable' && q.status_note" class="small muted">{{ t('原因：{r}', { r: q.status_note }) }}</p>
          </div>
          <span class="field-t">{{ t('發布代答') }}</span>
          <AnswerForm :question-id="id" @saved="answerSaved" />
          <div><button class="btn danger small" type="button" @click="staffDelOpen = true">{{ t('刪除這個問題') }}</button></div>
        </section>
      </template>
    </div>

    <Modal v-model:open="delOpen" :title="t('刪除問題')">
      <p v-if="!q?.answer_count">{{ t('刪除後無法復原，確定刪除？') }}</p>
      <template v-else>
        <p>{{ t('這個問題已經有校友回答，刪除要等校友工作部同意。') }}</p>
        <label class="field"><span>{{ t('刪除原因') }}</span><input v-model="delReason" type="text" maxlength="200" :placeholder="t('選填，給校友工作部看')" /></label>
      </template>
      <div class="actions">
        <button class="btn" type="button" style="background:var(--danger);border-color:var(--danger)" @click="deleteMine">{{ q?.answer_count ? t('送出刪除申請') : t('刪除') }}</button>
        <button class="btn plain" type="button" @click="delOpen = false">{{ t('取消') }}</button>
      </div>
    </Modal>

    <Modal v-model:open="statusOpen" :title="t('改成「{s}」', { s: t(STATUSES.find((s) => s.key === nextStatus)?.label ?? '') })">
      <p class="small">{{ nextStatus === 'hidden' ? t('其他同學會看不到這個問題。') : nextStatus === 'unable' ? t('只有提問者和校友工作部看得到。') : t('所有同學都看得到這個問題。') }}</p>
      <label v-if="nextStatus === 'unable'" class="field"><span>{{ t('原因') }}</span>
        <input v-model="note" type="text" maxlength="200" :placeholder="t('選填，提問者會看到')" />
      </label>
      <p class="muted tiny">{{ t('提問者會收到通知。') }}</p>
      <div class="actions">
        <button class="btn" type="button" @click="saveStatus">{{ t('確定') }}</button>
        <button class="btn plain" type="button" @click="statusOpen = false">{{ t('取消') }}</button>
      </div>
    </Modal>

    <Modal :open="!!removing" :title="t('刪除這則回答？')" @update:open="removing = null">
      <p class="small">{{ t('刪除後無法復原。如果刪完沒有任何回答，問題會改回「待回答」。') }}</p>
      <div class="actions">
        <button class="btn" type="button" style="background:var(--danger);border-color:var(--danger)" @click="removeAnswer">{{ t('刪除') }}</button>
        <button class="btn plain" type="button" @click="removing = null">{{ t('取消') }}</button>
      </div>
    </Modal>

    <Modal v-model:open="staffDelOpen" :title="t('刪除這個問題？')">
      <p class="small">{{ t('問題和所有回答都會刪除，無法復原。提問者會收到通知。') }}</p>
      <label class="field"><span>{{ t('原因') }}</span><input v-model="staffDelReason" type="text" maxlength="200" :placeholder="t('選填，例如：重複的問題')" /></label>
      <div class="actions">
        <button class="btn" type="button" style="background:var(--danger);border-color:var(--danger)" @click="staffDelete">{{ t('刪除') }}</button>
        <button class="btn plain" type="button" @click="staffDelOpen = false">{{ t('取消') }}</button>
      </div>
    </Modal>
  </main>
</template>
