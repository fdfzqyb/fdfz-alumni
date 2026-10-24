<script setup>
import { t } from '../i18n'
import { STATUS } from '../constants'

defineProps({ status: { type: String, required: true } })
</script>

<template>
  <span class="status" :class="STATUS[status].cls">{{ t(STATUS[status].label) }}</span>
</template>
