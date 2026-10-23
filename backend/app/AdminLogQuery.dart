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
  ORDER BY l.crtat DESC, l.id DESC
  LIMIT 200
''';
