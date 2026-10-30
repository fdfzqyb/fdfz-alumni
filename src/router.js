import { createRouter, createWebHistory } from 'vue-router'
import { authReady, fixPath, isStaff } from './auth'
import { accountUrl } from './fdfz'

// 登入、等待校園卡審核、改密碼都在帳號中心 account.fdfz.click，這裡的舊網址直接轉過去
const toAccount = (path) => () => {
  window.location.assign(accountUrl(path, location.origin + '/'))
  return false
}

// 每一頁都要登入且校園卡已審核；meta.staff：校友工作部
const routes = [
  { path: '/login', beforeEnter: toAccount('/login'), component: {} },
  { path: '/pending', beforeEnter: toAccount('/pending'), component: {} },
  { path: '/', component: () => import('./views/WallView.vue') },
  { path: '/q/:id(\\d+)', component: () => import('./views/QuestionView.vue') },
  { path: '/ask', component: () => import('./views/AskView.vue') },
  { path: '/q/:id(\\d+)/edit', component: () => import('./views/AskView.vue') },
  { path: '/mine', component: () => import('./views/MineView.vue') },
  { path: '/notifications', component: () => import('./views/NotificationsView.vue') },
  { path: '/account', component: () => import('./views/AccountView.vue') },
  { path: '/admin', component: () => import('./views/AdminView.vue'), meta: { staff: true } },
  { path: '/:pathMatch(.*)*', redirect: '/' },
]

export const router = createRouter({
  history: createWebHistory(),
  routes,
  scrollBehavior: (to, from, saved) => saved ?? { top: 0 },
})

router.beforeEach(async (to) => {
  await authReady
  // 沒登入、校園卡還沒通過、管理員重設了臨時密碼：都送到帳號中心處理，好了會回到這一頁
  const fix = fixPath()
  if (fix) {
    window.location.assign(accountUrl(fix, location.origin + to.fullPath))
    return false
  }
  if (to.meta.staff && !isStaff()) return '/account'
  return true
})
