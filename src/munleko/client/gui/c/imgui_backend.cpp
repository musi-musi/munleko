#include "imgui.h"
#include "imgui_impl_opengl3.h"

extern "C" {
    #include "imgui_impl_glfw.h"

    void imgui_backend_init(GLFWwindow *window) {
        ImGui_ImplGlfw_InitForOpenGL(window, 1);
        ImGui_ImplOpenGL3_Init(NULL);
    }

    void imgui_backend_deinit() {
        ImGui_ImplOpenGL3_Shutdown();
        ImGui_ImplGlfw_Shutdown();
    }

    void imgui_backend_newframe() {
        ImGui_ImplGlfw_NewFrame();
        ImGui_ImplOpenGL3_NewFrame();
    }

    void imgui_backend_render() {
        ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
    }

}