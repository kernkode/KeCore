kec.keys:bind({
    name = "_gizmoSelect",
    description = "Gizmo Select",
    Mapper = "MOUSE_BUTTON",
    Key = "MOUSE_LEFT",
    keydown = function() ExecuteCommand("+gizmoSelect") end,
    keyup = function() ExecuteCommand("-gizmoSelect") end
})

kec.keys:bind({
    name = "_gizmoTranslation",
    description = "Gizmo Translation",
    Mapper = "KEYBOARD",
    Key = "W",
    keydown = function() ExecuteCommand("+gizmoTranslation") end,
    keyup = function() ExecuteCommand("-gizmoTranslation") end
})

kec.keys:bind({
    name = "_gizmoRotation",
    description = "Gizmo Rotation",
    Mapper = "KEYBOARD",
    Key = "R",
    keydown = function() ExecuteCommand("+gizmoRotation") end,
    keyup = function() ExecuteCommand("-gizmoRotation") end
})

kec.keys:bind({
    name = "_gizmoEnd",
    description = "Gizmo End",
    Mapper = "KEYBOARD",
    Key = "RETURN",
    keydown = function() kec.gizmo:stop() end
})
