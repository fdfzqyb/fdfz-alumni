const pad = (n) => String(n).padStart(2, '0')

const hm = (d) => `${pad(d.getHours())}:${pad(d.getMinutes())}`

// 今年的寫「10/24 21:14」，往年的加上年份
export function stamp(value) {
  if (!value) return ''
  const d = new Date(value)
  const base = `${d.getMonth() + 1}/${d.getDate()} ${hm(d)}`
  return d.getFullYear() === new Date().getFullYear() ? base : `${d.getFullYear()}/${base}`
}

// Supabase 回傳的錯誤：資料庫函數 raise 的中文訊息直接顯示，其他的換成通用提示
export function errorText(error) {
  const msg = error?.message ?? ''
  if (/[一-鿿]/.test(msg)) return msg
  console.error(error)
  return '出了點問題，請稍後再試'
}
