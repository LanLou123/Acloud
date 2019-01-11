#include "UAVtex.h"

UAVtex::UAVtex(ID3D12Device* device, ID3D12GraphicsCommandList* cmdList, UINT width, UINT height, int deltatime)
{
	w = width;
	h = height;
	dt = deltatime;
	md3Device = device;
	BuildResources(cmdList);
	BuildRootSignature();
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
	texDesc.Format = DXGI_FORMAT_R32G32B32A32_FLOAT;
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


	std::vector<DirectX::XMFLOAT4> data( w*h , DirectX::XMFLOAT4(0, 0, 0, 0));

	D3D12_SUBRESOURCE_DATA subResourceData = {};
	subResourceData.pData = data.data();
	subResourceData.RowPitch = w * sizeof(DirectX::XMFLOAT4);//data in bytes per row
	subResourceData.SlicePitch = subResourceData.RowPitch*h;

	cmdList->ResourceBarrier(1, &CD3DX12_RESOURCE_BARRIER::Transition(mUav.Get(),
		D3D12_RESOURCE_STATE_COMMON, D3D12_RESOURCE_STATE_COPY_DEST));
	UpdateSubresources(cmdList, mUav.Get(), mUploadBuffer.Get(), 0, 0, num2DSubresources,
		&subResourceData);
	cmdList->ResourceBarrier(1, &CD3DX12_RESOURCE_BARRIER::Transition(mUav.Get(),
		D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_UNORDERED_ACCESS));
}

UINT UAVtex::DescriptorCount()const
{
	return 2;
}

void UAVtex::BuildDescriptors(CD3DX12_CPU_DESCRIPTOR_HANDLE hCpuDescriptor,
	CD3DX12_GPU_DESCRIPTOR_HANDLE hGpuDescriptor,
	UINT descriptorSize) {
	D3D12_SHADER_RESOURCE_VIEW_DESC srvDesc = {};
	srvDesc.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
	srvDesc.Format = DXGI_FORMAT_R32G32B32A32_FLOAT;
	srvDesc.ViewDimension = D3D12_SRV_DIMENSION_TEXTURE2D;
	srvDesc.Texture2D.MostDetailedMip = 0;
	srvDesc.Texture2D.MipLevels = 1;

	D3D12_UNORDERED_ACCESS_VIEW_DESC uavDesc = {};

	uavDesc.Format = DXGI_FORMAT_R32G32B32A32_FLOAT;
	uavDesc.ViewDimension = D3D12_UAV_DIMENSION_TEXTURE2D;
	uavDesc.Texture2D.MipSlice = 0;

	md3Device->CreateShaderResourceView(mUav.Get(), &srvDesc, hCpuDescriptor);
	md3Device->CreateUnorderedAccessView(mUav.Get(), nullptr, &uavDesc, hCpuDescriptor.Offset(1, descriptorSize));

	mSrvDescHandle = hGpuDescriptor;
	mUavDescHandle = hGpuDescriptor.Offset(1, descriptorSize);
}

void UAVtex::Update(const GameTimer& gt,
	ID3D12GraphicsCommandList* cmdList,
	ID3D12PipelineState* pso) {

	static float t = 0.0f;
	t += gt.DeltaTime();

	cmdList->SetPipelineState(pso);
	cmdList->SetComputeRootSignature(mRootSig.Get());
	if (t >= dt)
	{
		float curtime = gt.TotalTime();
		cmdList->SetComputeRootDescriptorTable(0, mUavDescHandle);
		cmdList->SetComputeRoot32BitConstants(1, 1, &curtime, 0);
		cmdList->ResourceBarrier(1, &CD3DX12_RESOURCE_BARRIER::Transition(
			mUav.Get(),
			D3D12_RESOURCE_STATE_GENERIC_READ, D3D12_RESOURCE_STATE_UNORDERED_ACCESS
		));
		UINT numGroupsX = w / 16;
		UINT numGroupsY = h / 16;


		cmdList->Dispatch(numGroupsX, numGroupsY, 1);

		t = 0.0f;

		cmdList->ResourceBarrier(1, &CD3DX12_RESOURCE_BARRIER::Transition(
			mUav.Get(),
			D3D12_RESOURCE_STATE_UNORDERED_ACCESS, D3D12_RESOURCE_STATE_GENERIC_READ
		));
	}
}

void UAVtex::BuildRootSignature()
{
	CD3DX12_DESCRIPTOR_RANGE uavTable0;
	uavTable0.Init(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 1, 0);

	CD3DX12_ROOT_PARAMETER slotRootParameter[2];

	slotRootParameter[0].InitAsDescriptorTable(1, &uavTable0);
	slotRootParameter[1].InitAsConstants(1, 0);

	CD3DX12_ROOT_SIGNATURE_DESC rootSigDesc(2, slotRootParameter, 0, nullptr,
		D3D12_ROOT_SIGNATURE_FLAG_NONE);

	ComPtr<ID3DBlob> serializedRootSig = nullptr;
	ComPtr<ID3DBlob> errorBlob = nullptr;
	HRESULT hr = D3D12SerializeRootSignature(&rootSigDesc, D3D_ROOT_SIGNATURE_VERSION_1,
		serializedRootSig.GetAddressOf(), errorBlob.GetAddressOf());

	if (errorBlob != nullptr)
	{
		::OutputDebugStringA((char*)errorBlob->GetBufferPointer());
	}
	ThrowIfFailed(hr);

	ThrowIfFailed(md3Device->CreateRootSignature(
		0,
		serializedRootSig->GetBufferPointer(),
		serializedRootSig->GetBufferSize(),
		IID_PPV_ARGS(mRootSig.GetAddressOf())));

}

ComPtr<ID3D12RootSignature> UAVtex::getRootSignature()
{
	return mRootSig;
}