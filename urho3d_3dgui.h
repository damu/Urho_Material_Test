#ifndef Urho3D_3DGUI_H
#define Urho3D_3DGUI_H

#include <vector>
#include <memory>

#include <Urho3D/Urho3D.h>
#include <Urho3D/Engine/Application.h>
#include <Urho3D/Engine/Engine.h>
#include <Urho3D/Core/Context.h>
#include <Urho3D/Scene/Scene.h>
#include <Urho3D/Resource/ResourceCache.h>
#include <Urho3D/Graphics/Camera.h>
#include <Urho3D/Graphics/Model.h>
#include <Urho3D/Graphics/AnimatedModel.h>
#include <Urho3D/Graphics/Material.h>
#include <Urho3D/IO/FileSystem.h>
#include <Urho3D/Input/Input.h>
#include <Urho3D/Input/InputEvents.h>

class urho3d_3dgui_element
{
public:
    Urho3D::Node* node=0;
    ~urho3d_3dgui_element()
    {
        if(node)
            node->Remove();
    }

    void SetSize(Urho3D::Vector3 size)
    {
        node->SetScale(Urho3D::Vector3(size.x_,size.z_,size.y_));
    }
};

class urho3d_3dgui_box : public urho3d_3dgui_element
{
public:
    Urho3D::SharedPtr<Urho3D::Material> material;
    Urho3D::Node* node_upleft=0;
    Urho3D::Node* node_upright=0;
    Urho3D::Node* node_downleft=0;
    Urho3D::Node* node_downright=0;

    urho3d_3dgui_box(Urho3D::Node* node,Urho3D::ResourceCache* cache);

    void SetColor(Urho3D::Color color)
    {
        material->SetShaderParameter("MatDiffColor",color);
    }
};

class urho3d_3dgui
{
    Urho3D::Node* node=0;
    Urho3D::Camera* camera=0;
    Urho3D::ResourceCache* cache=0;
    float offset_top=0;
    float offset_left=0;
public:
    std::vector<std::unique_ptr<urho3d_3dgui_element>> elements;

    urho3d_3dgui(Urho3D::Camera* camera,Urho3D::ResourceCache* cache);
    ~urho3d_3dgui()
    {
        node->Remove();
    }

    urho3d_3dgui_box* add_box(Urho3D::Vector3 position,Urho3D::Vector3 size);
    void resize();
};

#endif // Urho3D_3DGUI_H
