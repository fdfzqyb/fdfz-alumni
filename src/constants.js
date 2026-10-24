// 問題狀態：鍵名和資料庫的 alumni_q_status 一致，不能改；顯示文字可以改
export const STATUSES = [
  { key: 'hidden', label: '未公開', cls: 'st-hidden' },
  { key: 'open', label: '待回答', cls: 'st-open' },
  { key: 'contacting', label: '聯繫校友中', cls: 'st-contact' },
  { key: 'answered', label: '已回答', cls: 'st-answered' },
  { key: 'unable', label: '暫無法回答', cls: 'st-unable' },
]
export const STATUS = Object.fromEntries(STATUSES.map((s) => [s.key, s]))
// 其他同學看得到的狀態
export const PUBLIC_STATUSES = ['open', 'contacting', 'answered']

export const SITE_URL = 'https://alumni.fdfz.click'

// 「2019 屆校友・某某大學」，有真名時加在前面
export function alumniLabel(a, t) {
  const who = t('{y} 屆校友', { y: a.cohort })
  return [a.alumni_name, who, a.affiliation].filter(Boolean).join('・')
}
