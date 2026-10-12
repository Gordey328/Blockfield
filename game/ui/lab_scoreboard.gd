class_name LabScoreboard
extends PanelContainer
## ScoreboardView.cpp: team columns sorted by score, dead gray, local highlight.
var session: LocalSession
var main: Node3D
var per_player_colors: bool = true
var _columns: Array[RichTextLabel]=[]
var _spectators: Label
var _title: Label

func setup(app: Node3D, local_session: LocalSession) -> void:
	main=app
	session=local_session
	var content:=VBoxContainer.new()
	content.add_theme_constant_override("separation",14)
	add_child(content)
	_title=Label.new()
	_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size",22)
	content.add_child(_title)
	var teams:=HBoxContainer.new()
	teams.add_theme_constant_override("separation",32)
	content.add_child(teams)
	for index in 2:
		var label:=RichTextLabel.new()
		label.custom_minimum_size=Vector2(270,260)
		label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		label.bbcode_enabled=false
		label.add_theme_font_size_override("normal_font_size",17)
		teams.add_child(label)
		_columns.append(label)
	_spectators=Label.new()
	_spectators.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_spectators)

func get_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary]=[{"id":session.local_player_id(),"name":str(main.player_name),"team":session.team,"score":session.score,"deaths":int(session.get("player_deaths")),"alive":session.health>0,"local":true}]
	for target in session.targets:
		rows.append({"id":int(target.id),"name":str(target.get("name","Target %02d"%int(target.id))),"team":int(target.team),"score":int(target.get("score",target.get("kills",0))),"deaths":int(target.get("deaths",0)),"alive":bool(target.alive),"local":false})
	rows.sort_custom(func(a:Dictionary,b:Dictionary):return int(a.score)>int(b.score) if int(a.score)!=int(b.score) else int(a.id)<int(b.id))
	return rows

func _process(_delta: float) -> void:
	if session==null or not visible:return
	var ru:=TranslationServer.get_locale().begins_with("ru")
	_title.text=("ЛОКАЛЬНЫЙ МАТЧ" if ru else "OFFLINE MATCH")+" · "+session.mode.to_upper()
	var rows:=get_rows()
	for team_index in 2:
		var label:=_columns[team_index]
		label.clear()
		label.push_color(LabMap.team_color_for(session,team_index))
		var team_name := LabMap.team_name_for(session,team_index)
		var score:=str(session.team_scores[team_index])
		if session.mode=="ctf":score+=" / "+str(session.capture_limit)
		elif session.mode=="tc":score+=" / "+str(session.territories.size())
		label.add_text(team_name+"  "+score+"\n\n")
		label.pop()
		for row in rows:
			if int(row.team)!=team_index:continue
			# Native ScoreboardView shares the map palette for IDs; disabling it
			# makes IDs white independently of the following name/death tint.
			var id_color: Color=LabMap.modify_color(Color(LabMap.PLAYER_PALETTE[posmod(int(row.id),32)])) if per_player_colors else Color.WHITE
			label.push_color(id_color)
			label.add_text("#%02d"%int(row.id))
			label.pop()
			label.push_color(Color("f1e6ad") if bool(row.local) else (Color.WHITE if bool(row.alive) else Color("78848b")))
			label.add_text("   %s   %d\n"%[row.name,row.score])
			label.pop()
	var names:=PackedStringArray()
	for row in rows:
		if int(row.team)>=2:names.append("#%02d %s"%[row.id,row.name])
	_spectators.text=("Наблюдатели: " if ru else "Spectators: ")+", ".join(names)
