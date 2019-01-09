#pragma once

#include "./Common/d3dApp.h"
#include "./Common/d3dUtil.h"
#include "./Common/GameTimer.h"
#include <DirectXMath.h>
using Microsoft::WRL::ComPtr;

class UAVtex {
public:
	UAVtex(ID3D12Device* device, ID3D12GraphicsCommandList* cmdList, UINT width, UINT height, int deltatime);
	UAVtex(const UAVtex& rhs) = delete;
	UAVtex& operator=(const UAVtex& rhs) = delete;
	~UAVtex() = default;

	void BuildResources(ID3D12GraphicsCommandList* cmdList);
	void BuildDescriptors(
		CD3DX12_CPU_DESCRIPTOR_HANDLE hCpuDescriptor,
		CD3DX12_GPU_DESCRIPTOR_HANDLE hGpuDescriptor,
		UINT descriptorSize);

	void Update(const GameTimer& gt,
		ID3D12GraphicsCommandList* cmdList,
		ID3D12PipelineState* pso);

	void BuildRootSignature();

	UINT DescriptorCount()const;

	ComPtr<ID3D12RootSignature> getRootSignature();

	struct TexData {
		DirectX::XMFLOAT4 n1;
	};

	CD3DX12_GPU_DESCRIPTOR_HANDLE getGpuSrvDescHandle();
	CD3DX12_GPU_DESCRIPTOR_HANDLE getGpuUavDescHandle();

private:

	UINT w, h;

	int dt;

	ID3D12Device* md3Device = nullptr;

	ComPtr<ID3D12RootSignature> mRootSig;

	CD3DX12_GPU_DESCRIPTOR_HANDLE mSrvDescHandle;
	CD3DX12_GPU_DESCRIPTOR_HANDLE mUavDescHandle;

	Microsoft::WRL::ComPtr<ID3D12Resource> mUav = nullptr;
	Microsoft::WRL::ComPtr<ID3D12Resource> mUploadBuffer = nullptr;


};