import 'DBModel.dart';

class m_player extends DBModel {
  String name_last = ''; 
  String name_first = ''; 
  String name_middle = ''; 
  DateTime? date_birth = null; 
  int id_team = 0; 
  int id_position = 0; 
  int height = 0; 
  int weight = 0; 
  int pitching = 0; 
  int batting = 0; 
  bool flg_injury = false; 
  String path_img_face = ''; 
  String uniform_number = ''; 

  @override
  String get tableName => 'm_player';

  @override
  Map<String, dynamic> toMap() {
    return {
      "name_last" : name_last,
      "name_first" : name_first,
      "name_middle" : name_middle,
      "date_birth" : date_birth,
      "id_team" : id_team,
      "id_position" : id_position,
      "height" : height,
      "weight" : weight,
      "pitching" : pitching,
      "batting" : batting,
      "flg_injury" : flg_injury,
      "path_img_face" : path_img_face,
      "uniform_number" : uniform_number,
    };
  }
}