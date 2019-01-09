#include "UAVtex.h"

UAVtex::UAVtex(ID3D12Device* device, ID3D12GraphicsCommandList* cmdList, UINT width, UINT height)
{
	w = width;
	h = height;
	md3Device = device;
	BuildResources(cmdList);
}

CD3DX12_GPU_DESCRIPTOR_HANDLE UAVtex::getGpuSrvDescHandle() {
	return mSrvDescHandle;
}

CD3DX12_GPU_DESCRIPTOR_HANDLE UAVtex::getGpuUavDescHandle() {
	return mUavDescHandle;
}

void UAVtex::BuildResources(ID3D12GraphicsCommandList* cmdList)
{
	D3D12_RESOURCE_DESC texDesc;
	ZeroMemory(&texDesc, sizeof(D3D12_RESOURCE_DESC));
	texDesc.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
	texDesc.Alignment = 0;
	texDesc.Width = w;
	texDesc.Height = h;
	texDesc.DepthOrArraySize = 1;
	texDesc.MipLevels = 1;
	texDesc.Format = DXGI_FORMAT_R32_FLOAT;
	texDesc.SampleDesc.Count = 1;
	texDesc.SampleDesc.Quality = 0;
	texDesc.Layout = D3D12_TEXTURE_LAYOUT_UNKNOWN;
	texDesc.Flags = D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS;

	ThrowIfFailed(md3Device->CreateCommittedResource(
		&CD3DX12_HEAP_PROPERTIES(D3D12_HEAP_TYPE_DEFAULT),
		D3D12_HEAP_FLAG_NONE,
		&texDesc,
		D3D12_RESOURCE_STATE_COMMON,
		nullptr,
		IID_PPV_ARGS(&mUav)
	));

	const UINT num2DSubresources = texDesc.DepthOrArraySize*texDesc.MipLevels;
	const UINT64 uploadBufferSize = GetRequiredIntermediateSize(mUav.Get(), 0, num2DSubresources);

	ThrowIfFailed(md3Device->CreateCommittedResource(
		&CD3DX12_HEAP_PROPERTIES(D3D12_HEAP_TYPE_UPLOAD),
		D3D12_HEAP_FLAG_NONE,
		&CD3DX12_RESOURCE_DESC::Buffer(uploadBufferSize),
		D3D12_RESOURCE_STATE_GENERIC_READ,
		nullptr,
		IID_PPV_ARGS(mUploadBuffer.GetAddressOf())
	));

	TexData defaultdata = { DirectX::XMFLOAT3(0,0,0) };
	std::vector<TexData> data( w*h ,defaultdata);

	D3D12_SUBRESOURCE_DATA subResourceData = {};
	subResourceData.pData = data.data();
	subResourceData.RowPitch = w * sizeof(TexData);//data in bytes per row
	subResourceData.SlicePitch = subResourceData.RowPitch*h;

	cmdList->ResourceBarrier(1, &CD3DX12_RESOURCE_BARRIER::Transition(mUav.Get(),
		D3D12_RESOURCE_STATE_COMMON, D3D12_RESOURCE_STATE_COPY_DEST));
	UpdateSubresources(cmdList, mUav.Get(), mUploadBuffer.Get(), 0, 0, num2DSubresources,
		&subResourceData);
	cmdList->ResourceBarrier(1, &CD3DX12_RESOURCE_BARRIER::Transition(mUav.Get(),
		D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_UNORDERED_ACCESS));
}

void UAVtex::BuildDescriptors(CD3DX12_CPU_DESCRIPTOR_HANDLE hCpuDescriptor,
	CD3DX12_GPU_DESCRIPTOR_HANDLE hGpuDescriptor,
	UINT descriptorSize) {
	D3D12_SHADER_RESOURCE_VIEW_DESC srvDesc = {};
	srvDesc.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
	srvDesc.Format = DXGI_FORMAT_R32_FLOAT;
	srvDesc.ViewDimension = D3D12_SRV_DIMENSION_TEXTURE2D;
	srvDesc.Texture2D.MostDetailedMip = 0;
	srvDesc.Texture2D.MipLevels = 1;

	D3D12_UNORDERED_ACCESS_VIEW_DESC uavDesc = {};

	uavDesc.Format = DXGI_FORMAT_R32_FLOAT;
	uavDesc.ViewDimension = D3D12_UAV_DIMENSION_TEXTURE2D;
	uavDesc.Texture2D.MipSlice = 0;

	md3Device->CreateShaderResourceView(mUav.Get(), &srvDesc, hCpuDescriptor);
	md3Device->CreateUnorderedAccessView(mUav.Get(), nullptr, &uavDesc, hCpuDescriptor.Offset(1, descriptorSize));

	mSrvDescHandle = hGpuDescriptor;
	mUavDescHandle = hGpuDescriptor.Offset(1, descriptorSize);
}