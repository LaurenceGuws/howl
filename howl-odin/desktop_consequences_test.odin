package main

import "core:testing"

@(test)
desktop_consequence_policy_flashes_only_bell_and_attention_families :: proc(t: ^testing.T) {
	bell := Consequence_Info{kind = u8(Bridge_Consequence_Kind.Bell)}
	testing.expect_value(t, consequence_action_for(bell), Desktop_Consequence_Action.Attention)
	message := Consequence_Info{kind = u8(Bridge_Consequence_Kind.Notification)}
	message.metadata[0] = 1
	testing.expect_value(t, consequence_action_for(message), Desktop_Consequence_Action.Consume)
	steal := message
	steal.metadata[0] = 2
	testing.expect_value(t, consequence_action_for(steal), Desktop_Consequence_Action.Attention)
	request := message
	request.metadata[0] = 3
	testing.expect_value(t, consequence_action_for(request), Desktop_Consequence_Action.Attention)
}

@(test)
desktop_consequence_policy_mirrors_headless_reply_fallback :: proc(t: ^testing.T) {
	clipboard := Consequence_Info{kind = u8(Bridge_Consequence_Kind.Clipboard), reply_required = 1}
	testing.expect_value(t, consequence_action_for(clipboard), Desktop_Consequence_Action.Reply_Clipboard_Empty)
	pointer := Consequence_Info{kind = u8(Bridge_Consequence_Kind.Pointer_Shape), reply_required = 1}
	testing.expect_value(t, consequence_action_for(pointer), Desktop_Consequence_Action.Reply_Pointer_Default)
	color := Consequence_Info{kind = u8(Bridge_Consequence_Kind.Color_Preference), reply_required = 1}
	testing.expect_value(t, consequence_action_for(color), Desktop_Consequence_Action.Reply_Color_Dark)
	container := Consequence_Info{kind = u8(Bridge_Consequence_Kind.Container), reply_required = 1}
	container.metadata[0] = 12
	testing.expect_value(t, consequence_action_for(container), Desktop_Consequence_Action.Reply_Container_Screen)
	container.metadata[0] = 11
	testing.expect_value(t, consequence_action_for(container), Desktop_Consequence_Action.Reply_Container_Decline)
}

@(test)
desktop_consequence_big_endian_container_reply_is_exact :: proc(t: ^testing.T) {
	body: [8]u8
	testing.expect(t, write_u32_be(body[0:4], 24))
	testing.expect(t, write_u32_be(body[4:8], 132))
	testing.expect_value(t, body, [8]u8{0,0,0,24,0,0,0,132})
}
