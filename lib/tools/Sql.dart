class Sql {

  // m_team
  static String selectTeams() {
    return '''
      SELECT
        id,
        url_npb_players
      FROM m_team
    ''';
  }

  // t_predict_team
  
  static String selectPredictNPBTeams() {
    return '''
      SELECT
        t_predict_team.id AS id_predict,
        m_user.id AS id_user,
        m_user.name_last,
        m_team.name_short,
        m_team.id_league,
        int_rank,
        flg_champion
      FROM t_predict_team
          LEFT OUTER JOIN m_user ON m_user.id = t_predict_team.id_user
          LEFT OUTER JOIN m_team ON m_team.id = t_predict_team.id_team
      ORDER BY m_user.id, id_league, int_rank
    ''';
  }

  static String insertMPlayerKeys() {
    return 'name_last, name_first, name_middle, date_birth, id_team, id_position, height, weight, pitching, batting, flg_injury, path_img_face, uniform_number';
  }

  static String insertMPlayerPlaceholders() {
    return '@name_last, @name_first, @name_middle, @date_birth, @id_team, @id_position, @height, @weight, @pitching, @batting, @flg_injury, @path_img_face, @uniform_number';
  }

  static String insertMPlayerSQL() {
    return 'INSERT INTO m_player (' + insertMPlayerKeys() + ') VALUES (' + insertMPlayerPlaceholders() + ') RETURNING id;';
  }
}