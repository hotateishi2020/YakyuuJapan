class DBModel {
  String tableName = '';

  int id = 0; 
  bool flg_delete = false; 
  DateTime crtat = DateTime.now(); 
  int crtby = 0; 
  String crtenv = ''; 
  String crtpgm = ''; 
  DateTime updat = DateTime.now(); 
  int updby = 0; 
  String updenv = ''; 
  String updpgm = ''; 

  Map<String, dynamic> toMap() {
    return {
      "id" : id,
      "flg_delete" : flg_delete,
      "crtat" : crtat,
      "crtby" : crtby,
      "crtenv" : crtenv,
      "crtpgm" : crtpgm,
      "updat" : updat,
      "updby" : updby,
      "updenv" : updenv,
      "updpgm" : updpgm,
    };
  }
}