extends SceneTree
var assertions:=0
var failures:=0
func check(value:bool,label:String) -> void:
	assertions+=1
	if not value:failures+=1;push_error("FAIL: "+label)
func _initialize() -> void:
	var focus:=LabFocus.new()
	focus.accept_distances([NAN,INF,0.8,-2.0,12.0,20.0,8.0,16.0])
	check(is_equal_approx(focus.target_distance,14.0),"median valid source depths, near threshold excluded")
	focus.accept_distances([NAN,0.5])
	check(is_equal_approx(focus.target_distance,14.0),"no visible hit keeps previous target")
	focus.accept_distances([10.0,18.0,12.0])
	check(is_equal_approx(focus.target_distance,12.0),"odd median")
	focus.target_distance=1.0;focus.distance=20.0;focus.advance(0.1)
	check(absf(focus.distance-1.0/0.09)<0.0001,"reciprocal autofocus speed .4")
	focus.advance(10.0)
	check(is_equal_approx(focus.distance,1.0),"focus approaches without overshoot")
	focus.target_distance=20.0;focus.adjust_wheel(true)
	check(not focus.automatic and absf(focus.target_distance-1.0/0.06)<0.0001,"wheel disables autofocus and adds .01 diopters")
	for i in range(200):focus.adjust_wheel(false)
	check(is_equal_approx(focus.target_distance,128.0),"manual far clamp128")
	for i in range(200):focus.adjust_wheel(true)
	check(is_equal_approx(focus.target_distance,1.0),"manual near clamp1")
	print("FOCUS TESTS: %d assertions, %d failures"%[assertions,failures])
	quit(1 if failures else 0)
