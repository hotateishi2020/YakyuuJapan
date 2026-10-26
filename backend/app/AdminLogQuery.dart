/// Category choices come from saved history, independently of the visible page.
const selectAdminLogCategories = r'''
  SELECT DISTINCT BTRIM(category) AS category FROM t_system_log
  WHERE NULLIF(BTRIM(category), '') IS NOT NULL ORDER BY category
''';

/// Apply the visible log type before LIMIT so background traffic cannot evict clicks.
/// Untyped legacy records retain the API's existing operation fallback.
const selectAdminOperationLogs = r'''
  SELECT l.id, l.crtat, l.crtby, COALESCE(u.name_last, '') AS name_user,
         l.method, l.category, l.code, l.memo, l.url, l.txt_detail
  FROM t_system_log l
  LEFT JOIN m_user u ON u.id = l.crtby
  WHERE (COALESCE(l.txt_detail, '') !~ '"log_type"[[:space:]]*:'
      OR l.txt_detail ~ '"log_type"[[:space:]]*:[[:space:]]*"操作"')
    AND ($1::text = ''
      OR CAST(l.crtby AS text) = $1::text
      OR COALESCE(u.name_last, '') ILIKE '%' || $1::text || '%'
      OR COALESCE(u.name_first, '') ILIKE '%' || $1::text || '%')
    AND ($2::text = '' OR BTRIM(l.category) = $2::text)
  ORDER BY l.crtat DESC, l.id DESC
  LIMIT 200
''';
