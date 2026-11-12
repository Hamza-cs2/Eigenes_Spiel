class_name Projectile
extends Hitbox
## A Hitbox that flies in a straight line. Destroyed when it hits a Hurtbox or the world.
## Layer 5 (EnemyAttack), Mask 1 (World).

@export var lifetime := 3.0

var direction := Vector2.RIGHT
var speed := 200.0


func launch(dir: Vector2, p_speed: float, p_damage: int, p_source: Node2D) -> void:
	direction = dir
	speed = p_speed
	damage = p_damage
	source = p_source
	rotation = dir.angle()


func _ready() -> void:
	start_active = true
	super()
	monitoring = true
	body_entered.connect(func(_b: Node2D) -> void: queue_free())
	hit_landed.connect(func(_h: Hurtbox) -> void: queue_free())
	get_tree().create_timer(lifetime, false).timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta
