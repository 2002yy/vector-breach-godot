class_name GdUnitSmokeTestSuite
extends GdUnitTestSuite


func test_arithmetic() -> void:
	assert_int(1 + 1).is_equal(2)


func test_string_contains() -> void:
	assert_str("矢量突袭").contains("突袭")
