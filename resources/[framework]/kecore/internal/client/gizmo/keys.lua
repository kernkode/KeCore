-- Las teclas del gizmo (mover y rotar entidades a mano) son de desarrollo: fuera de él no hay
-- nada que las use y en cambio sí molestan — cuatro mapeos más en los ajustes del juego del
-- jugador y un ExecuteCommand en cada clic izquierdo. `kec.gizmo` sigue existiendo; lo que se
-- deja de registrar es el input.
if not kec.dev then return end

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
