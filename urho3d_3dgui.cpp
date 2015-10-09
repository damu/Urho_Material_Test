#include <iostream>
#include "urho3d_3dgui.h"

using namespace std;
using namespace Urho3D;

urho3d_3dgui_box::urho3d_3dgui_box(Urho3D::Node* node,Urho3D::ResourceCache* cache)
{
    this->node=node->CreateChild();
    AnimatedModel* boxObject=this->node->CreateComponent<AnimatedModel>();
    boxObject->SetCastShadows(true);
    boxObject->SetModel(cache->GetResource<Model>("Models/3dgui_box.mdl"));
    boxObject->GetSkeleton().GetBone("upleft")->animated_=false;
    boxObject->GetSkeleton().GetBone("upright")->animated_=false;
    boxObject->GetSkeleton().GetBone("downleft")->animated_=false;
    boxObject->GetSkeleton().GetBone("downright")->animated_=false;
    node_upleft=this->node->GetChild("upleft",true);
    node_downleft=this->node->GetChild("upright",true); // these two are switched for some reason
    node_upright=this->node->GetChild("downleft",true); // these two are switched for some reason
    node_downright=this->node->GetChild("downright",true);
    //node_upleft->Translate(Vector3(0,0,0),TS_PARENT);
    node_upleft->SetPosition(Vector3(0,0,0));
    node_downleft->SetPosition(Vector3(0,0,node_downleft->GetPosition().z_));
    node_upright->SetPosition(Vector3(node_upright->GetPosition().x_,0,0));

    material=cache->GetResource<Material>("Materials/3dgui.xml");
    material=material->Clone();
    boxObject->SetMaterial(material);
}

urho3d_3dgui::urho3d_3dgui(Urho3D::Camera* camera,Urho3D::ResourceCache* cache) : cache(cache),camera(camera)
{
    node=camera->GetNode()->CreateChild();
    node->Translate(Vector3(0,0,0.2));
    node->Pitch(90);
    resize();
}

urho3d_3dgui_box* urho3d_3dgui::add_box(Urho3D::Vector3 position,Vector3 size)
{
    elements.emplace_back(new urho3d_3dgui_box(node,cache));
    auto e=(urho3d_3dgui_box*)elements[elements.size()-1].get();
    //e->SetSize(size);
    e->node->Translate(Vector3(-offset_left*9.05,0,-offset_top*9.05));  // 9.05 makes the GUI barelly touch the window border
    return e;
}

void urho3d_3dgui::resize()
{
    auto fov=camera->GetFov();
    camera->SetFov(90);
    Urho3D::Vector3 v=camera->GetNode()->WorldToLocal(camera->ScreenToWorldPoint(Urho3D::Vector3(1,0,0)));  // 1,0 is top right in screen coordinates and +x +y in world coordinates
    camera->SetFov(fov);
    v.x_/=v.z_*10; // normalize to 0.1 because the coordinates are "multiplied" with the near clip distance and we want the GUI to be 0.1 in front of the camera
    v.y_/=v.z_*10;
    v.z_=0.1;
cout<<v.x_<<" "<<v.y_<<" "<<v.z_<<endl;

    offset_left=v.x_*1;
    offset_top=v.y_*1;
    node->SetScale(v);
}
