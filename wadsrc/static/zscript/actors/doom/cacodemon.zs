//===========================================================================
//
// Cacodemon
//
//===========================================================================
class Cacodemon : Actor
{
	Default
	{
		Health 400;
		Radius 31;
		Height 56;
		Mass 400;
		Speed 8;
		PainChance 128;
		Monster;
		+FLOAT +NOGRAVITY
		SeeSound "caco/sight";
		PainSound "caco/pain";
		DeathSound "caco/death";
		ActiveSound "caco/active";
		Obituary "$OB_CACO";
		HitObituary "$OB_CACOHIT";
		Tag "$FN_CACO";
	}
	States
	{
	Spawn:
		HEAD A 10 A_Look;
		Loop;
	See:
		HEAD A 3 A_Chase;
		Loop;
	Missile:
		HEAD B 5 A_FaceTarget;
		HEAD C 5 A_FaceTarget;
		HEAD D 5 BRIGHT A_HeadAttack;
		Goto See;
	Pain:
		HEAD E 3;
		HEAD E 3 A_Pain;
		HEAD F 6;
		Goto See;
	Death:
		HEAD G 8;
		HEAD H 8 A_Scream;
		HEAD I 8;
		HEAD J 8;
		HEAD K 8 A_NoBlocking;
		HEAD L -1 A_SetFloorClip;
		Stop;
	Raise:
		HEAD L 8 A_UnSetFloorClip;
		HEAD KJIHG 8;
		Goto See;
	}
}

//===========================================================================
//
// Cacodemon plasma ball
//
//===========================================================================
class CacodemonBall : Actor
{
	Default
	{
		Radius 6;
		Height 8;
		Speed 10;
		FastSpeed 20;
		Damage 5;
		Projectile;
		+RANDOMIZE
		+ZDOOMTRANS
		RenderStyle "Add";
		Alpha 1;
		SeeSound "caco/attack";
		DeathSound "caco/shotx";
	}
	States
	{
	Spawn:
		BAL2 AB 4 BRIGHT;
		Loop;
	Death:
		BAL2 CDE 6 BRIGHT;
		Stop;
	}
}


//===========================================================================
//
// Code (must be attached to Actor)
//
//===========================================================================

extend class Actor
{
	void A_HeadAttack()
	{
		let targ = target;
		if (targ)
		{
			if (CheckMeleeRange())
			{
				int damage = random[pr_headattack](1, 6) * 10;
				A_PlaySound (AttackSound, CHAN_WEAPON);
				int newdam = target.DamageMobj (self, self, damage, "Melee");
				targ.TraceBleed (newdam > 0 ? newdam : damage, self);
			}
			else
			{
				// launch a missile
				SpawnMissile (targ, "CacodemonBall");
			}
		}
	}
}
