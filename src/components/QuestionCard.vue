<script setup>
import { t } from '../i18n'
import { stamp } from '../format'
import { alumniLabel } from '../constants'
import Icon from './Icon.vue'
import StatusTag from './StatusTag.vue'

// 問題牆、我的提問、後台共用的卡片；top 是按「有幫助」排第一的代答（可以沒有）
defineProps({ q: { type: Object, required: true }, top: Object, showAuthor: Boolean })
</script>

<template>
  <router-link class="card q" :to="`/q/${q.id}`">
    <div class="hstack">
      <StatusTag :status="q.status" />
      <span class="tag">{{ q.category_name }}</span>
      <span v-if="q.is_mine" class="tag">{{ t('我問的') }}</span>
    </div>
    <h3>{{ q.title }}</h3>
    <p class="excerpt">{{ q.body }}</p>
    <div v-if="top" class="answer peek">
      <span class="who"><Icon name="cap" :size="18" />{{ alumniLabel(top, t) }}</span>
      <p>{{ top.body }}</p>
    </div>
    <div class="q-foot">
      <span><Icon name="hand" />{{ t('我也想問 {n}', { n: q.metoo_count }) }}</span>
      <span v-if="q.answer_count"><Icon name="cap" />{{ t('{n} 則代答', { n: q.answer_count }) }}</span>
      <span v-if="showAuthor">{{ q.author_name ?? t('匿名') }}<template v-if="q.author_student_id"> · {{ q.author_student_id }}</template></span>
      <span>{{ stamp(q.published_at ?? q.created_at) }}</span>
    </div>
  </router-link>
</template>
