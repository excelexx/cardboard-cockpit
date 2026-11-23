extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var a := Image.load_from_file(args[0])
	var b := Image.load_from_file(args[1])
	var w: int = mini(a.get_width(),b.get_width())
	var h: int = mini(a.get_height(),b.get_height())
	var sum := 0.0
	var peak := 0.0
	var out := Image.create(w,h,false,Image.FORMAT_RGB8)
	for y in range(h):
		for x in range(w):
			var ca := a.get_pixel(x,y); var cb := b.get_pixel(x,y)
			var d := Vector3(ca.r-cb.r,ca.g-cb.g,ca.b-cb.b)
			sum += d.length_squared()/3.0
			peak = maxf(peak,maxf(absf(d.x),maxf(absf(d.y),absf(d.z))))
			var g: float = clampf(d.length()*6.0,0.0,1.0)
			out.set_pixel(x,y,Color(g,g,g))
	var mse: float = sum/float(w*h)
	print("PSNR ",(10.0*log(1.0/maxf(mse,1e-12))/log(10.0))," dB  RMS ",sqrt(mse)*100.0,"%  peak ",peak)
	if args.size()>2: out.save_png(args[2])
	quit(0)
