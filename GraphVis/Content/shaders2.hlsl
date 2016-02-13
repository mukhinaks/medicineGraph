
#if 0
$ubershader (COMPUTE INJECTION|MOVE|REDUCTION|(SIMULATION EULER|RUNGE_KUTTA))|(DRAW POINT|LINE)
#endif

#define BLOCK_SIZE	256


struct PARTICLE3D {
	float3	Position; // 3 coordinates
	float3	Velocity;
	float4	Color0;
	float	Size0;
	float	TotalLifeTime;
	float	LifeTime;
	int		LinksPtr;
	int		LinksCount;
	float3	Acceleration;
	float	Mass;
	float	Charge;
};


struct LinkId {
	int id;
};


struct PARAMS {
	float4x4	View;
	float4x4	Projection;
	int			MaxParticles;
	float		DeltaTime;
	float		LinkSize;
};


struct Link {
	int par1;
	int par2;
	float length;
	float force2;
	float3 orientation;
};

cbuffer CB1 : register(b0) { 
	PARAMS Params; 
};

SamplerState						Sampler				: 	register(s0);
Texture2D							Texture 			: 	register(t0);

RWStructuredBuffer<PARTICLE3D>		particleBufferSrc	: 	register(u0);
RWStructuredBuffer<float>			energyBuffer		:	register(u1);
StructuredBuffer<PARTICLE3D>		GSResourceBuffer	:	register(t1);

StructuredBuffer<LinkId>			linksPtrBuffer		:	register(t2);
StructuredBuffer<Link>				linksBuffer			:	register(t3);


#ifdef REDUCTION
groupshared float sh_energy[BLOCK_SIZE];
#endif // REDUCTION


#ifdef SIMULATION
groupshared PARTICLE3D sh_particles[BLOCK_SIZE];
groupshared uint counter;
#endif // SIMULATION




/*-----------------------------------------------------------------------------
	Simulation :
-----------------------------------------------------------------------------*/

struct BodyState
{
	float3 Position;
	float3 Velocity;
	float3 Acceleration;
	uint id;
};


struct Derivative
{
	float3 dxdt;
	float3 dvdt;
};


#ifdef SIMULATION
float3 SpringForce( in float3 bodyState, in float3 otherBodyState, float linkLength )
{
	float3 R			= otherBodyState - bodyState;			
	float Rabs			= length( R ) + 0.1f;
	float absForce		= 0.1f * ( Rabs - linkLength ) / ( Rabs );
	return mul( absForce, R );
}


float3 RepulsionForce( in float3 bodyState, in float3 otherBodyState, float charge1, float charge2 )
{
	float3 R			= otherBodyState - bodyState;			
	float Rsquared		= R.x * R.x + R.y * R.y + R.z * R.z + 0.1f;
	float Rsixth		= Rsquared * Rsquared * Rsquared;
	float invRCubed		= - 10000.0f * charge1 * charge2  / sqrt( Rsixth );
	return mul( invRCubed, R );
}



float3 Acceleration( in int totalNum, in int particleId, in uint groupIndex  )
{
	PARTICLE3D prt = particleBufferSrc[particleId];
	PARTICLE3D other;

	float3 acc = {0,0,0};
	float3 deltaForce = {0, 0, 0};
	float invMass = 1 / prt.Mass;

	
	[allow_uav_condition] for ( int lNum = 0; lNum < prt.LinksCount; ++ lNum ) {

		int otherId = linksBuffer[linksPtrBuffer[prt.LinksPtr + lNum].id].par1;

		if ( otherId == particleId ) {
			otherId = linksBuffer[linksPtrBuffer[prt.LinksPtr + lNum].id].par2;
		}

		other = particleBufferSrc[otherId];
		deltaForce += SpringForce( prt.Position, other.Position, linksBuffer[linksPtrBuffer[prt.LinksPtr + lNum].id].length );

	}

	
	uint tileNum = 0;
	for ( int i = 0; i < Params.MaxParticles; i += BLOCK_SIZE )
	{
		int srcIndex = tileNum * BLOCK_SIZE + groupIndex;
		sh_particles[groupIndex] = particleBufferSrc[srcIndex];
		GroupMemoryBarrierWithGroupSync();

		for ( int otherIndex = 0; otherIndex < BLOCK_SIZE; ++otherIndex )
		{
			other = sh_particles[otherIndex];
			deltaForce += RepulsionForce( prt.Position, other.Position, prt.Charge, other.Charge );
		}
		GroupMemoryBarrierWithGroupSync();
		++tileNum;
	}
	
	/*
	uint tileNum = 0;
	if ( groupIndex == 0 ) counter = 0;
	while ( counter < Params.MaxParticles )
	{
		int srcIndex = tileNum * BLOCK_SIZE + groupIndex;
		sh_particles[groupIndex] = particleBufferSrc[srcIndex];
		GroupMemoryBarrierWithGroupSync();

		for ( int otherIndex = 0; otherIndex < BLOCK_SIZE; ++otherIndex )
		{
			other = sh_particles[otherIndex];
			deltaForce += RepulsionForce( prt.Position, other.Position, prt.Charge, other.Charge );
		}

		if ( groupIndex == 0 ) counter += BLOCK_SIZE;

		GroupMemoryBarrierWithGroupSync();
		++tileNum;
		
	}*/

	
	/*
	for ( int i = 0; i < totalNum; ++i ) {
		other = particleBufferSrc[ i ];
		deltaForce += RepulsionForce( prt.Position, other.Position, prt.Charge, other.Charge );
	}
	*/

	acc += mul( deltaForce, invMass );
	acc -= mul ( prt.Velocity, 1.6f );

	return acc;
}




void IntegrateEUL_SHARED( inout BodyState state, in uint numParticles, in uint groupIndex )
{
	
	state.Acceleration	= Acceleration( numParticles, state.id, groupIndex );
}

#endif //SIMULATION

#ifdef COMPUTE


#ifdef INJECTION
[numthreads( BLOCK_SIZE, 1, 1 )]
void CSMain( 
	uint3 groupID			: SV_GroupID,
	uint3 groupThreadID 	: SV_GroupThreadID, 
	uint3 dispatchThreadID 	: SV_DispatchThreadID,
	uint  groupIndex 		: SV_GroupIndex
)
{
	int id = dispatchThreadID.x;


	if (id < Params.MaxParticles) {
		PARTICLE3D p = particleBufferSrc[id];
		
		if (p.LifeTime < p.TotalLifeTime) {
			
			particleBufferSrc[id] = p;
		}
	}
}
#endif // INJECTION

#ifdef SIMULATION

[numthreads( BLOCK_SIZE, 1, 1 )]
void CSMain( 
	uint3 groupID			: SV_GroupID,
	uint3 groupThreadID 	: SV_GroupThreadID, 
	uint3 dispatchThreadID 	: SV_DispatchThreadID,
	uint  groupIndex 		: SV_GroupIndex
)
{
	int id = dispatchThreadID.x;

	if (id < Params.MaxParticles) {
		PARTICLE3D p = particleBufferSrc[ id ];
		
		BodyState state;
		state.Position		=	p.Position;
		state.Velocity		=	p.Velocity;
		state.Acceleration	=	p.Acceleration;
		state.id			=	id;

#ifdef EULER

			IntegrateEUL_SHARED( state, Params.MaxParticles, groupIndex );

#endif // EULER


#ifdef RUNGE_KUTTA
	
			IntegrateEUL_SHARED( state, Params.MaxParticles, groupIndex );

#endif // RUNGE_KUTTA

	//		float color	= p.Size0;

	//		float maxColor = 10.0f;
	//		color = saturate( color / maxColor );

	//		p.Color0	=	float4( color, - 0.5f * color +1.0f, - 0.5f * color +1.0f, 1 );

			p.Acceleration = state.Acceleration;

			particleBufferSrc[id] = p;
	}
}

#endif // SIMULATION

#ifdef MOVE
[numthreads( BLOCK_SIZE, 1, 1 )]
void CSMain( 
	uint3 groupID			: SV_GroupID,
	uint3 groupThreadID 	: SV_GroupThreadID, 
	uint3 dispatchThreadID 	: SV_DispatchThreadID,
	uint  groupIndex 		: SV_GroupIndex
)
{
	int id = dispatchThreadID.x;

	if (id < Params.MaxParticles) {
		PARTICLE3D p = particleBufferSrc[ id ];
		
		p.Position.xyz += mul( p.Velocity, Params.DeltaTime );
		p.Velocity += mul( p.Acceleration, Params.DeltaTime );
		particleBufferSrc[ id ] = p;
	}
}
#endif // MOVE


#ifdef REDUCTION

#if 0
[numthreads( BLOCK_SIZE, 1, 1 )]
void CSMain( 
	uint3 groupID			: SV_GroupID,
	uint3 groupThreadID 	: SV_GroupThreadID, 
	uint3 dispatchThreadID 	: SV_DispatchThreadID,
	uint  groupIndex 		: SV_GroupIndex
)
{
	int id = dispatchThreadID.x;
	sh_energy[groupIndex] = 0;

	if (id < Params.MaxParticles) {
		PARTICLE3D p = GSResourceBuffer[ id ];
		float scalarAcc = length(p.Acceleration);

		scalarAcc *= scalarAcc;
		sh_energy[groupIndex] = scalarAcc * p.Mass * p.Mass;
	}
	GroupMemoryBarrierWithGroupSync();


	/*
	// with divergence ( working threads are 0, 2, 4 ... when s = 1 )
	for ( unsigned int s = 1; s < BLOCK_SIZE; s *= 2 )
	{
		if ( groupIndex%(2*s) == 0 )
		{
			sh_energy[groupIndex] += sh_energy[groupIndex + s];
		}
		GroupMemoryBarrierWithGroupSync();
	}
	if( groupIndex == 0 )
	{
		energyBuffer[groupID.x] = sh_energy[0];
	}
	*/

	/*
	// without divergence
	for ( unsigned int s = 1; s < BLOCK_SIZE; s *= 2 )
	{
		int index = 2 * s * groupIndex;
		if ( index < BLOCK_SIZE )
		{
			sh_energy[index] += sh_energy[index + s];
		}
		GroupMemoryBarrierWithGroupSync();
	}
	if( groupIndex == 0 )
	{
		energyBuffer[groupID.x] = sh_energy[0];
	}
	*/

	
	// sequential addressing without bank conflicts and without divergence:
	for ( unsigned int s = BLOCK_SIZE/2; s > 0; s >>= 1 )
	{
		if ( groupIndex < s )
		{
			sh_energy[groupIndex] += sh_energy[groupIndex + s];
		}
		GroupMemoryBarrierWithGroupSync();
	}
	if( groupIndex == 0 )
	{
		energyBuffer[groupID.x] = sh_energy[0];
	}
	
}
#endif


[numthreads( BLOCK_SIZE/2, 1, 1 )]
void CSMain( 
	uint3 groupID			: SV_GroupID,
	uint3 groupThreadID 	: SV_GroupThreadID, 
	uint3 dispatchThreadID 	: SV_DispatchThreadID,
	uint  groupIndex 		: SV_GroupIndex
)
{
//	int id = dispatchThreadID.x;
	int id = groupID.x*BLOCK_SIZE + groupIndex;

	// load data into shared memory:
	PARTICLE3D p1 = GSResourceBuffer[ id ];
	PARTICLE3D p2 = GSResourceBuffer[ id + BLOCK_SIZE/2 ];
	float scalarAcc1 = length(p1.Acceleration);
	float scalarAcc2 = length(p2.Acceleration);
	scalarAcc1 *= scalarAcc1;
	scalarAcc2 *= scalarAcc2;
	sh_energy[groupIndex] = scalarAcc1 * p1.Mass * p1.Mass + scalarAcc2 * p2.Mass * p2.Mass;
	GroupMemoryBarrierWithGroupSync();

	// sequential addressing without bank conflicts and without divergence:
	for ( unsigned int s = BLOCK_SIZE/4; s > 32; s >>= 1 )
	{
		if ( groupIndex < s )
		{
			sh_energy[groupIndex] += sh_energy[groupIndex + s];
		}
		GroupMemoryBarrierWithGroupSync();
	}

	if ( groupIndex < 32 )
	{
		sh_energy[groupIndex] += sh_energy[groupIndex + 32];
		sh_energy[groupIndex] += sh_energy[groupIndex + 16];
		sh_energy[groupIndex] += sh_energy[groupIndex + 8];
		sh_energy[groupIndex] += sh_energy[groupIndex + 4];
		sh_energy[groupIndex] += sh_energy[groupIndex + 2];
		sh_energy[groupIndex] += sh_energy[groupIndex + 1];
	}

	if( groupIndex == 0 )
	{
		energyBuffer[groupID.x] = sh_energy[0];
	}

}


#endif // REDUCTION





// Get accelerations of particles, sort accelerations in grouphared memory
// Write max acceleration from each thread group into the output buffer

#ifdef MAX_ACCEL


groupshared float accelSorted[BLOCK_SIZE];

groupshared uint invValues	[BLOCK_SIZE];	
groupshared uint offset		[BLOCK_SIZE*4];
groupshared uint destinations[BLOCK_SIZE];
groupshared uint zeros;




[numthreads( BLOCK_SIZE, 1, 1 )]
void CSMain( 
	uint3 groupID			: SV_GroupID,
	uint3 groupThreadID 	: SV_GroupThreadID, 
	uint3 dispatchThreadID 	: SV_DispatchThreadID,
	uint  groupIndex 		: SV_GroupIndex
)
{

	int id = dispatchThreadID.x;

	float3 accel3 = particleBufferSrc[id];

	float3 accel = length( accel3 );

	accelSorted[groupIndex] = accel;

	// wait until accelSorted is populated
	GroupMemoryBarrierWithGroupSync();



}





#endif // MAX_ACCEL





#endif // COMPUTE




/*-----------------------------------------------------------------------------
	Rendering :
-----------------------------------------------------------------------------*/


#ifdef DRAW


struct VSOutput {
int vertexID : TEXCOORD0;
};

struct GSOutput {
	float4	Position : SV_Position;
	float2	TexCoord : TEXCOORD0;
	float4	Color    : COLOR0;
};



VSOutput VSMain( uint vertexID : SV_VertexID )
{
VSOutput output;
output.vertexID = vertexID;
return output;
}


float Ramp(float f_in, float f_out, float t) 
{
	float y = 1;
	t = saturate(t);
	
	float k_in	=	1 / f_in;
	float k_out	=	-1 / (1-f_out);
	float b_out =	-k_out;	
	
	if (t<f_in)  y = t * k_in;
	if (t>f_out) y = t * k_out + b_out;
	
	
	return y;
}


#ifdef POINT
[maxvertexcount(6)]
void GSMain( point VSOutput inputPoint[1], inout TriangleStream<GSOutput> outputStream )
{

	GSOutput p0, p1, p2, p3;
	
//	VSOutput prt = inputPoint[0];

	PARTICLE3D prt = GSResourceBuffer[ inputPoint[0].vertexID ];
	
	if (prt.LifeTime >= prt.TotalLifeTime ) {
		return;
	}
	

		float factor = saturate(prt.LifeTime / prt.TotalLifeTime);

//		float sz = lerp( prt.Size0, prt.Size1, factor )/2;

		float sz = prt.Size0;

		float time = prt.LifeTime;

		float4 color	=	prt.Color0;

		float4 pos		=	float4( prt.Position.xyz, 1 );

		float4 posV		=	mul( pos, Params.View );

//		p0.Position = mul( float4( position + float2( sz, sz), 0, 1 ), Params.Projection );
		p0.Position = mul( posV + float4( sz, sz, 0, 0 ) , Params.Projection );
//		p0.Position = posP + float4( sz, sz, 0, 0 );		
		p0.TexCoord = float2(1,1);
		p0.Color = color;

//		p1.Position = mul( float4( position + float2(-sz, sz), 0, 1 ), Params.Projection );
		p1.Position = mul( posV + float4(-sz, sz, 0, 0 ) , Params.Projection );
//		p1.Position = posP + float4(-sz, sz, 0, 0 );
		p1.TexCoord = float2(0,1);
		p1.Color = color;

//		p2.Position = mul( float4( position + float2(-sz,-sz), 0, 1 ), Params.Projection );
		p2.Position = mul( posV + float4(-sz,-sz, 0, 0 ) , Params.Projection );
//		p2.Position = posP + float4(-sz,-sz, 0, 0 );
		p2.TexCoord = float2(0,0);
		p2.Color = color;

//		p3.Position = mul( float4( position + float2( sz,-sz), 0, 1 ), Params.Projection );
		p3.Position = mul( posV + float4( sz,-sz, 0, 0 ) , Params.Projection );
//		p3.Position = posP + float4( sz,-sz, 0, 0 );
		p3.TexCoord = float2(1,0);
		p3.Color = color;

		outputStream.Append(p0);
		outputStream.Append(p1);
		outputStream.Append(p2);
		outputStream.RestartStrip();
		outputStream.Append(p0);
		outputStream.Append(p2);
		outputStream.Append(p3);
		outputStream.RestartStrip();

}

#endif // POINT


#ifdef LINE
[maxvertexcount(2)]
void GSMain( point VSOutput inputLine[1], inout LineStream<GSOutput> outputStream )
{
	GSOutput p1, p2;

	Link lk = linksBuffer[ inputLine[0].vertexID ];
	PARTICLE3D end1 = GSResourceBuffer[ lk.par1 ];
	PARTICLE3D end2 = GSResourceBuffer[ lk.par2 ];
	float4 pos1 = float4( end1.Position.xyz, 1 );
	float4 pos2 = float4( end2.Position.xyz, 1 );

	float4 posV1	=	mul( pos1, Params.View );
	float4 posV2	=	mul( pos2, Params.View );
	

//	PARTICLE3D end1 = GSResourceBuffer[inputLine[0].vertexID];
//	float4 pos1 = float4( end1.Position.xyz, 1 );
//	float4 pos2 = float4( end1.Position.xyz + float3(5,0,0), 1 );

//	float4 posV1	=	mul( pos1, Params.View );
//	float4 posV2	=	mul( pos2, Params.View );

	p1.Position		=	mul( posV1, Params.Projection );
	p2.Position		=	mul( posV2, Params.Projection );

	p1.TexCoord		=	float2(0, 0);
	p2.TexCoord		=	float2(0, 0);

	p1.Color		=	end1.Color0;
	p2.Color		=	end2.Color0;

	outputStream.Append(p1);
	outputStream.Append(p2);
	outputStream.RestartStrip(); 


}

#endif // LINE



#ifdef LINE
float4 PSMain( GSOutput input ) : SV_Target
{
	return float4(input.Color.rgb,1);
}
#endif // LINE



#ifdef POINT
float4 PSMain( GSOutput input ) : SV_Target
{
	return Texture.Sample( Sampler, input.TexCoord ) * float4(input.Color.rgb,1);
}
#endif // POINT


#endif //DRAW


