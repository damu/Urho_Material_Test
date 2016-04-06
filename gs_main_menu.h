#ifndef GS_MAIN_MENU_H
#define GS_MAIN_MENU_H

#include <memory>

#include <Urho3D/UI/Window.h>
#include <Urho3D/UI/Text.h>

#include "game_state.h"

/// The main menu displayed when starting the game.
class gs_main_menu : public game_state
{
public:
    Urho3D::Text* window_text;
    Urho3D::Window* window;

    gs_main_menu();
    void update(Urho3D::StringHash eventType,Urho3D::VariantMap& eventData);
    void HandleKeyDown(Urho3D::StringHash eventType,Urho3D::VariantMap& eventData);

    URHO3D_OBJECT(gs_main_menu,game_state);
};

#endif // GS_MAIN_MENU_H
