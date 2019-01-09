#pragma once

#include "./Common/d3dApp.h"
#include "./Common/d3dUtil.h"
#include "./Common/GameTimer.h"
#include <DirectXMath.h>

class UAVtex {
	UAVtex(ID3D12Device* device, ID3D12GraphicsCommandList* cmdList);
	UAVtex(const UAVtex& rhs) = delete;
	UAVtex& operator=(const UAVtex& rhs) = delete;
	~UAVtex() = default;

	void BuildResources(ID3D12GraphicsCommandList* cmdList);

};