/*
 * infamous-probe: checks, in a few seconds, that this device can run a Windows ARM64 build of
 * inFAMOUS Reborn under Proton: the process runs as native ARM64, the guest memory layout the
 * PS3 runtime reserves (4 GB windows, low 4 GB trap) is available, access violations reach a
 * __try handler and a vectored handler, and Direct3D 12 (device, feature level 11_0, flip-model
 * swapchain, D24S8, BC1-3 textures, HLSL 5.0 compile through d3dcompiler_47) works.
 *
 * Writes infamous-probe.log next to the exe and shows a few colours in a window.
 * Build: aarch64-w64-mingw32-clang -O2 -fms-extensions probe.c -o infamous-probe.exe -static
 *        -ld3d12 -ldxgi -ld3dcompiler_47 -luser32 -lgdi32
 */
#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d12.h>
#include <dxgi1_6.h>
#include <d3dcompiler.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdint.h>

static FILE* g_log;
static int g_fail;
static void out(const char* fmt, ...)
{
    va_list a;
    va_start(a, fmt); vprintf(fmt, a); va_end(a);
    if (g_log) { va_start(a, fmt); vfprintf(g_log, fmt, a); va_end(a); fflush(g_log); }
    fflush(stdout);
}
static void check(int ok, const char* what, const char* detail)
{
    out("[%s] %s%s%s\n", ok ? " ok " : "FAIL", what, detail ? ": " : "", detail ? detail : "");
    if (!ok) g_fail++;
}

static LONG WINAPI veh(EXCEPTION_POINTERS* ep)
{
    static volatile LONG seen;
    if (ep->ExceptionRecord->ExceptionCode == EXCEPTION_ACCESS_VIOLATION && !seen) {
        seen = 1;
    }
    return EXCEPTION_CONTINUE_SEARCH;
}

static int probe_av(volatile uint8_t* p)
{
    __try { return p[0]; }
    __except (GetExceptionCode() == EXCEPTION_ACCESS_VIOLATION ? EXCEPTION_EXECUTE_HANDLER : EXCEPTION_CONTINUE_SEARCH) { return -1; }
}

static void probe_cpu_mem(void)
{
    char b[256];
    USHORT pm = 0, nm = 0;
    BOOL (WINAPI *isw2)(HANDLE, USHORT*, USHORT*) =
        (BOOL (WINAPI *)(HANDLE, USHORT*, USHORT*))(void*)GetProcAddress(GetModuleHandleA("kernel32.dll"), "IsWow64Process2");
    if (isw2 && isw2(GetCurrentProcess(), &pm, &nm)) {
        snprintf(b, sizeof b, "process machine 0x%04X (0 = native), host machine 0x%04X (0xAA64 = ARM64)", pm, nm);
        check(pm == 0 && nm == 0xAA64, "native ARM64 process", b);
    } else {
        SYSTEM_INFO si; GetNativeSystemInfo(&si);
        snprintf(b, sizeof b, "processor architecture %u (12 = ARM64)", si.wProcessorArchitecture);
        check(si.wProcessorArchitecture == 12, "native ARM64 process", b);
    }
    SYSTEM_INFO si; GetSystemInfo(&si);
    snprintf(b, sizeof b, "%lu", si.dwNumberOfProcessors);
    check(si.dwNumberOfProcessors >= 4, "logical processors", b);
    MEMORYSTATUSEX ms = { sizeof ms };
    GlobalMemoryStatusEx(&ms);
    snprintf(b, sizeof b, "%llu MB total, %llu MB free", ms.ullTotalPhys >> 20, ms.ullAvailPhys >> 20);
    check(ms.ullTotalPhys >= (6ull << 30), "physical memory", b);

    /* vm.h: reserve 2 x 4 GB, then 4 GB at a 4 GB aligned address inside it, commit main memory */
    uint8_t* probe = (uint8_t*)VirtualAlloc(NULL, 0x200000000ull, MEM_RESERVE, PAGE_NOACCESS);
    check(probe != NULL, "reserve 8 GB address range", NULL);
    if (probe) {
        uint8_t* aligned = (uint8_t*)(((uintptr_t)probe + 0xFFFFFFFFull) & ~0xFFFFFFFFull);
        VirtualFree(probe, 0, MEM_RELEASE);
        uint8_t* base = (uint8_t*)VirtualAlloc(aligned, 0x100000000ull, MEM_RESERVE, PAGE_NOACCESS);
        snprintf(b, sizeof b, "%p", (void*)aligned);
        check(base == aligned, "reserve 4 GB at a 4 GB boundary", b);
        if (base) {
            uint8_t* m = (uint8_t*)VirtualAlloc(base + 0x10000000u, 0x10000000u, MEM_COMMIT, PAGE_READWRITE);
            if (m) { memset(m, 0x5A, 0x10000000u); }
            check(m != NULL && m[0x0FFFFFFF] == 0x5A, "commit and touch 256 MB of guest memory", NULL);
            AddVectoredExceptionHandler(1, veh);
            int r = probe_av(base + 0x80000000u);
            check(r == -1, "access violation caught by __try/__except (vectored handler installed)", NULL);
            VirtualFree(base, 0, MEM_RELEASE);
        }
    }
    size_t got = 0;
    for (uintptr_t a = 0x10000u; a < 0x100000000ull; a += 0x10000000ull) {
        SIZE_T len = 0x10000000u - (a == 0x10000u ? 0x10000u : 0);
        void* p = VirtualAlloc((void*)a, len, MEM_RESERVE, PAGE_NOACCESS);
        if (p) { got += len; VirtualFree(p, 0, MEM_RELEASE); }
    }
    snprintf(b, sizeof b, "%zu MB of the low 4 GB free to reserve", got >> 20);
    check(1, "guest-pointer trap window", b);
}

static LRESULT CALLBACK wndproc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcA(h, m, w, l);
}

static const char k_hlsl[] =
    "struct V { float4 p : SV_Position; float2 t : TEXCOORD0; };\n"
    "V vs(uint i : SV_VertexID) { V o; o.t = float2((i << 1) & 2, i & 2); o.p = float4(o.t * float2(2, -2) + float2(-1, 1), 0, 1); return o; }\n"
    "Texture2D tx : register(t0); SamplerState ss : register(s0);\n"
    "cbuffer C : register(b0) { float4 tint; float4 k[4]; };\n"
    "float4 ps(V v) : SV_Target { float4 c = tx.Sample(ss, v.t) * tint; [loop] for (int j = 0; j < 4; j++) c += k[j] * ddx(v.t.x); return c; }\n";

static void probe_d3d12(void)
{
    char b[512];
    HMODULE dc = LoadLibraryA("d3dcompiler_47.dll");
    check(dc != NULL, "load d3dcompiler_47.dll", NULL);
    ID3DBlob *vsb = NULL, *psb = NULL, *err = NULL;
    HRESULT hr = D3DCompile(k_hlsl, sizeof k_hlsl - 1, "probe", NULL, NULL, "vs", "vs_5_0", D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, &vsb, &err);
    snprintf(b, sizeof b, "hr 0x%08lX%s%s", (unsigned long)hr, err ? " " : "", err ? (const char*)ID3D10Blob_GetBufferPointer(err) : "");
    check(SUCCEEDED(hr), "D3DCompile vs_5_0", b);
    if (err) { ID3D10Blob_Release(err); err = NULL; }
    hr = D3DCompile(k_hlsl, sizeof k_hlsl - 1, "probe", NULL, NULL, "ps", "ps_5_0", D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, &psb, &err);
    snprintf(b, sizeof b, "hr 0x%08lX%s%s", (unsigned long)hr, err ? " " : "", err ? (const char*)ID3D10Blob_GetBufferPointer(err) : "");
    check(SUCCEEDED(hr), "D3DCompile ps_5_0", b);
    if (err) { ID3D10Blob_Release(err); err = NULL; }

    IDXGIFactory4* f = NULL;
    hr = CreateDXGIFactory2(0, &IID_IDXGIFactory4, (void**)&f);
    snprintf(b, sizeof b, "hr 0x%08lX", (unsigned long)hr);
    check(SUCCEEDED(hr), "CreateDXGIFactory2", b);
    if (!f) return;
    IDXGIAdapter1* ad = NULL;
    if (SUCCEEDED(IDXGIFactory4_EnumAdapters1(f, 0, &ad))) {
        DXGI_ADAPTER_DESC1 d; IDXGIAdapter1_GetDesc1(ad, &d);
        snprintf(b, sizeof b, "%ls, %llu MB video memory, %llu MB shared", d.Description,
                 (unsigned long long)d.DedicatedVideoMemory >> 20, (unsigned long long)d.SharedSystemMemory >> 20);
        check(1, "adapter", b);
    }
    ID3D12Device* dev = NULL;
    hr = D3D12CreateDevice((IUnknown*)ad, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void**)&dev);
    snprintf(b, sizeof b, "hr 0x%08lX", (unsigned long)hr);
    check(SUCCEEDED(hr), "D3D12CreateDevice (feature level 11_0)", b);
    if (!dev) return;
    const DXGI_FORMAT fmts[] = { DXGI_FORMAT_D24_UNORM_S8_UINT, DXGI_FORMAT_BC1_UNORM, DXGI_FORMAT_BC2_UNORM,
                                 DXGI_FORMAT_BC3_UNORM, DXGI_FORMAT_R10G10B10A2_UNORM, DXGI_FORMAT_B8G8R8A8_UNORM };
    const char* names[] = { "D24_UNORM_S8_UINT", "BC1_UNORM", "BC2_UNORM", "BC3_UNORM", "R10G10B10A2_UNORM", "B8G8R8A8_UNORM" };
    for (int i = 0; i < 6; i++) {
        D3D12_FEATURE_DATA_FORMAT_SUPPORT fs = { fmts[i] };
        HRESULT h2 = ID3D12Device_CheckFeatureSupport(dev, D3D12_FEATURE_FORMAT_SUPPORT, &fs, sizeof fs);
        snprintf(b, sizeof b, "format %s support1 0x%08X", names[i], (unsigned)fs.Support1);
        check(SUCCEEDED(h2) && fs.Support1 != 0, b, NULL);
    }
    D3D12_COMMAND_QUEUE_DESC qd = { D3D12_COMMAND_LIST_TYPE_DIRECT };
    ID3D12CommandQueue* q = NULL;
    hr = ID3D12Device_CreateCommandQueue(dev, &qd, &IID_ID3D12CommandQueue, (void**)&q);
    check(SUCCEEDED(hr), "command queue", NULL);
    if (!q) return;

    WNDCLASSA wc = { 0 }; wc.lpfnWndProc = wndproc; wc.hInstance = GetModuleHandleA(NULL); wc.lpszClassName = "infamousprobe";
    RegisterClassA(&wc);
    HWND w = CreateWindowExA(0, "infamousprobe", "inFAMOUS probe", WS_OVERLAPPEDWINDOW | WS_VISIBLE, 0, 0, 1280, 720, NULL, NULL, wc.hInstance, NULL);
    DXGI_SWAP_CHAIN_DESC1 sd = { 0 };
    sd.Width = 1280; sd.Height = 720; sd.Format = DXGI_FORMAT_B8G8R8A8_UNORM; sd.SampleDesc.Count = 1;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT; sd.BufferCount = 3; sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
    IDXGISwapChain1* sc1 = NULL;
    hr = IDXGIFactory4_CreateSwapChainForHwnd(f, (IUnknown*)q, w, &sd, NULL, NULL, &sc1);
    snprintf(b, sizeof b, "hr 0x%08lX", (unsigned long)hr);
    check(SUCCEEDED(hr), "flip-model swapchain (3 x B8G8R8A8 1280x720)", b);
    if (!sc1) return;
    IDXGISwapChain3* sc = NULL;
    IDXGISwapChain1_QueryInterface(sc1, &IID_IDXGISwapChain3, (void**)&sc);

    D3D12_DESCRIPTOR_HEAP_DESC hd = { D3D12_DESCRIPTOR_HEAP_TYPE_RTV, 3 };
    ID3D12DescriptorHeap* rh = NULL;
    ID3D12Device_CreateDescriptorHeap(dev, &hd, &IID_ID3D12DescriptorHeap, (void**)&rh);
    UINT inc = ID3D12Device_GetDescriptorHandleIncrementSize(dev, D3D12_DESCRIPTOR_HEAP_TYPE_RTV);
    D3D12_CPU_DESCRIPTOR_HANDLE h0;
    rh->lpVtbl->GetCPUDescriptorHandleForHeapStart(rh, &h0);   /* out-pointer form, as in the runtime's rsx_d3d12_abi.h */
    ID3D12Resource* bb[3] = { 0 };
    for (UINT i = 0; i < 3; i++) {
        IDXGISwapChain3_GetBuffer(sc, i, &IID_ID3D12Resource, (void**)&bb[i]);
        D3D12_CPU_DESCRIPTOR_HANDLE h = { h0.ptr + i * inc };
        ID3D12Device_CreateRenderTargetView(dev, bb[i], NULL, h);
    }
    ID3D12CommandAllocator* ca = NULL; ID3D12GraphicsCommandList* cl = NULL; ID3D12Fence* fe = NULL;
    ID3D12Device_CreateCommandAllocator(dev, D3D12_COMMAND_LIST_TYPE_DIRECT, &IID_ID3D12CommandAllocator, (void**)&ca);
    ID3D12Device_CreateCommandList(dev, 0, D3D12_COMMAND_LIST_TYPE_DIRECT, ca, NULL, &IID_ID3D12GraphicsCommandList, (void**)&cl);
    ID3D12GraphicsCommandList_Close(cl);
    ID3D12Device_CreateFence(dev, 0, D3D12_FENCE_FLAG_NONE, &IID_ID3D12Fence, (void**)&fe);
    HANDLE ev = CreateEventA(NULL, FALSE, FALSE, NULL);
    UINT64 fv = 0;
    LARGE_INTEGER fq, t0, t1; QueryPerformanceFrequency(&fq); QueryPerformanceCounter(&t0);
    int frames = 0, presents_ok = 1;
    for (; frames < 240; frames++) {
        MSG msg; while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageA(&msg); }
        UINT i = IDXGISwapChain3_GetCurrentBackBufferIndex(sc);
        ID3D12CommandAllocator_Reset(ca);
        ID3D12GraphicsCommandList_Reset(cl, ca, NULL);
        D3D12_RESOURCE_BARRIER br = { D3D12_RESOURCE_BARRIER_TYPE_TRANSITION };
        br.Transition.pResource = bb[i]; br.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
        br.Transition.StateBefore = D3D12_RESOURCE_STATE_PRESENT; br.Transition.StateAfter = D3D12_RESOURCE_STATE_RENDER_TARGET;
        ID3D12GraphicsCommandList_ResourceBarrier(cl, 1, &br);
        const float col[4] = { (frames / 80) == 0, (frames / 80) == 1, (frames / 80) == 2, 1 };
        D3D12_CPU_DESCRIPTOR_HANDLE h = { h0.ptr + i * inc };
        ID3D12GraphicsCommandList_ClearRenderTargetView(cl, h, col, 0, NULL);
        br.Transition.StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET; br.Transition.StateAfter = D3D12_RESOURCE_STATE_PRESENT;
        ID3D12GraphicsCommandList_ResourceBarrier(cl, 1, &br);
        ID3D12GraphicsCommandList_Close(cl);
        ID3D12CommandQueue_ExecuteCommandLists(q, 1, (ID3D12CommandList**)&cl);
        if (FAILED(IDXGISwapChain3_Present(sc, 1, 0))) presents_ok = 0;
        ID3D12CommandQueue_Signal(q, fe, ++fv);
        ID3D12Fence_SetEventOnCompletion(fe, fv, ev);
        WaitForSingleObject(ev, 2000);
    }
    QueryPerformanceCounter(&t1);
    snprintf(b, sizeof b, "%d frames in %.2f s (%.1f fps with vsync), red, green, blue for ~1.3 s each",
             frames, (double)(t1.QuadPart - t0.QuadPart) / fq.QuadPart,
             frames / ((double)(t1.QuadPart - t0.QuadPart) / fq.QuadPart));
    check(presents_ok, "clear + present loop", b);
}

int main(void)
{
    char path[MAX_PATH]; DWORD n = GetModuleFileNameA(NULL, path, MAX_PATH);
    while (n && path[n - 1] != '\\' && path[n - 1] != '/') n--;
    strcpy(path + n, "infamous-probe.log");
    g_log = fopen(path, "w");
    out("infamous-probe 1 (inFAMOUS Reborn ARM64 port)\n");
    probe_cpu_mem();
    probe_d3d12();
    out("%s: %d check(s) failed\n", g_fail ? "RESULT FAIL" : "RESULT OK", g_fail);
    if (g_log) fclose(g_log);
    return g_fail ? 1 : 0;
}
