;******************************************************************************
; DOS Ray-tracing rendering Demo
; by 0xAA55
; 2021-2-17
;
; This program is a DOS `COM` program which is able to be run in native DOS
; system in Real mode x86 CPU
;******************************************************************************


bits 16
org 0x100

%define MapCast_Iterate 12
%define SampleDepth 12

segment .text
;******************************************************************************
; The entry point of the program: Start
; Must be placed at first of the file.
;******************************************************************************
Start:
call SetupVideoMode
call RenderScreen
call RestoreVideoMode

;Exit program
int 0x20
ret

segment .data
CamPos_X dd 0.0
CamPos_Y dd 2.0
CamPos_Z dd 7.0
NumSpheres equ 3
SizeOf_Sphere dw (3 + 1 + 3) * 4
Spheres:
	;Position
	;Radius
	;Color
Sphere1:
	dd  0.0, 2.0, 0.0
	dd  2.0
	dd  0.7, 0.9, 0.1
Sphere2:
	dd  1.0, 1.0, 2.0
	dd  1.0
	dd  0.1, 0.7, 0.9
Sphere3:
	dd -3.0, 1.0, 0.0
	dd  1.0
	dd  0.9, 0.1, 0.7

BB_XNeg dd -4.5
BB_XPos dd  2.5
BB_YNeg dd -0.5
BB_YPos dd  4.5
BB_ZNeg dd -0.5
BB_ZPos dd  3.5

SkyColor_R dd 0.2
SkyColor_G dd 0.5
SkyColor_B dd 0.8

LightDir_X dd 1.0
LightDir_Y dd -1.0
LightDir_Z dd 1.0
LightPow equ 20

LightColor_R dd 1.0
LightColor_G dd 0.8
LightColor_B dd 0.6

FogColor_R dd 0.8
FogColor_G dd 0.9
FogColor_B dd 1.0

FogDistance dd 100.0

segment .text
;******************************************************************************
; Setup video mode to 0x13: Graphic mode, 320x200 resolution, 256 colors.
; The VRAM buffer is 0xA000:0x0000
; Each byte of the buffer represents the color index of a palette.
; The previous video mode will be saved.
;******************************************************************************
SetupVideoMode:
	;Get current display mode
	mov ah, 0x0f
	int 0x10
	mov [SavedVideoMode], al

	;Set display mode to 320x200 graphic 256-color mode
	mov ax, 0x0013
	int 0x10

	call SetupPalette
	ret

;******************************************************************************
; Setup our specific palette to use our color-system.
; We use RGB:233 color format to encode the color index, and it's easier to
; implement the ordered-dithering algorithm to gain a better appearance.
;******************************************************************************
SetupPalette:
	;Set up palette
	mov bl, 0
	mov cx, 256
	.LoopSetPalette:
		push cx
		mov dx, 0x03C8
		mov al, bl ;The current color index
		out dx, al

		inc dl ;0x03C9 port

		;Red: 2 bits
		and al, 0x03
		mov bh, 0x55
		mul bh
		out dx, al

		;Green: 3 bits
		mov al, bl
		mov cl, 2
		shr al, cl
		and al, 0x07
		mov bh, 0x49
		mul bh
		out dx, al

		;Blue: 3 bits
		mov al, bl
		mov cl, 5
		shr al, cl
		and al, 0x07
		mul bh
		out dx, al

		;Increase the color index
		inc bl
		pop cx
	loop .LoopSetPalette
	ret


;******************************************************************************
; Pickup the best color for pixel position of `Pixel_X` and `Pixel_Y` with
; the color value of `Pixel_R` `Pixel_G` `Pixel_B`.
; Returns the best color index through register `AL`.
;******************************************************************************
PickColor:
	mov al, [Pixel_X]
	and al, 0xf
	mov ah, [Pixel_Y]
	and ah, 0xf
	mov cl, 4
	shl ah, cl
	or al, ah
	mov ah, 0

	mov bx, DitherMatrix
	xlatb
	mov dl, al
	mov cl, 2
	shr dl, cl
	inc cl
	shr al, cl

	add [Pixel_R], dl
	jnc .RedReady
	mov byte [Pixel_R], 0xFF
.RedReady:
	add [Pixel_G], al
	jnc .GreenReady
	mov byte [Pixel_G], 0xFF
.GreenReady:
	add [Pixel_B], al
	jnc .BlueReady
	mov byte [Pixel_B], 0xFF
.BlueReady:

	and byte [Pixel_R], 0xC0
	and byte [Pixel_G], 0xE0
	and byte [Pixel_B], 0xE0
	mov al, [Pixel_R]
	shr al, cl ;cl = 3
	or al, [Pixel_G]
	shr al, cl
	or al, [Pixel_B]
	ret

;******************************************************************************
; Restore the video mode to the saved video mode.
; The saved video mode was saved by calling `SetupVideoMode`.
;******************************************************************************
RestoreVideoMode:
	;Restore video mode
	mov ax, [SavedVideoMode]
	int 0x10
	ret

;******************************************************************************
; Render the scene
;******************************************************************************
RenderScreen:
	push bp
	mov bp, sp

	%define Local_Cam_U bp - 16
	%define Local_Cam_V bp - 12
	%define Local_Cam_W bp - 8
	%define Local_Cam_D bp - 4
	%define Local_Alloc 16

	sub sp, Local_Alloc

	mov ax, 0xa000
	mov es, ax

	fld dword [FM175]
	fstp dword [Local_Cam_W]

	;Do some initialize
	fld dword [LightDir_X]
	fmul st0
	fld dword [LightDir_Y]
	fmul st0
	fadd
	fld dword [LightDir_Z]
	fmul st0
	fadd
	fsqrt
	fld st0
	fdivr dword [LightDir_X]
	fstp dword [LightDir_X]
	fld st0
	fdivr dword [LightDir_Y]
	fstp dword [LightDir_Y]
	fdivr dword [LightDir_Z]
	fstp dword [LightDir_Z]

	;di: Used to write display buffer
	xor di, di

	;Loop for scan lines
	mov word [Pixel_Y], 0
	.LoopLines:
		;Calculate Ray-V
		mov ax, [Pixel_Y]
		add ax, ax
		sub ax, [Y_Res]
		not ax
		inc ax
		mov [Local_Cam_V], ax
		fild word [Local_Cam_V]
		fidiv word [Y_Res]
		fstp dword [Local_Cam_V]

		;Loop for pixels per scan line
		mov word [Pixel_X], 0
		.LoopPixels:
			;Calculate Ray-U
			mov ax, [Pixel_X]
			add ax, ax
			sub ax, [X_Res]
			mov [Local_Cam_U], ax
			fild word [Local_Cam_U]
			fidiv word [Y_Res]
			fst dword [Local_Cam_U]

			;Normalize Ray
			fmul st0
			fld dword [Local_Cam_V]
			fmul st0
			fadd
			fadd dword [F30625]
			fsqrt
			fst dword [Local_Cam_D]
			fdivr dword [Local_Cam_U]
			fstp dword [RayDir_X]
			fld dword [Local_Cam_V]
			fdiv dword [Local_Cam_D]
			fstp dword [RayDir_Y]
			fld dword [Local_Cam_W]
			fdiv dword [Local_Cam_D]
			fstp dword [RayDir_Z]

			; Render the current pixel color
			call RenderScene
			stosb
			inc word [Pixel_X]
			cmp word [Pixel_X], 320
		jb .LoopPixels
		inc word [Pixel_Y]
		cmp word [Pixel_Y], 200
	jb .LoopLines

	; Wait for any keystroke to exit
	mov ah, 0x07
	int 0x21

	mov sp, bp
	pop bp
	ret

;******************************************************************************
; Pick up a color that represents the sky from the `RayDir` vector.
;******************************************************************************
GetSkyColor:
	; SunLum = Dot(RayDir, -LightDir)
	fld dword [RayDir_X]
	fmul dword [LightDir_X]
	fld dword [RayDir_Y]
	fmul dword [LightDir_Y]
	fadd
	fld dword [RayDir_Z]
	fmul dword [LightDir_Z]
	fadd
	fchs

	; SunLum = Max(SunLum, 0)
	fld st0
	fabs
	fadd
	fidiv word [C2]

	; SunLum = Pow(SunLum, LightPow)
	%if LightPow > 0
		fld st0
		%rep LightPow - 1
		fmul st1
		%endrep
		fmul
	%endif

	; FogDensity = 1 - abs(RayDir_y)
	fld1
	fld dword [RayDir_Y]
	fabs
	fsub

	; Mix(SkyColor, FogColor, FogDensity)
	fld st0
	fmul dword [FogColor_R]
	fstp dword [GetSkyColor_R]
	fld st0
	fmul dword [FogColor_G]
	fstp dword [GetSkyColor_G]
	fld st0
	fmul dword [FogColor_B]
	fstp dword [GetSkyColor_B]

	; 1 - FogDensity
	fld1
	fsubr
	fld st0
	fmul dword [SkyColor_R]
	fadd dword [GetSkyColor_R]
	fstp dword [GetSkyColor_R]
	fld st0
	fmul dword [SkyColor_G]
	fadd dword [GetSkyColor_G]
	fstp dword [GetSkyColor_G]

	fmul dword [SkyColor_B]
	fadd dword [GetSkyColor_B]
	fstp dword [GetSkyColor_B]

	; LightColor
	fld st0
	fmul dword [LightColor_R]
	fadd dword [GetSkyColor_R]
	fstp dword [GetSkyColor_R]
	fld st0
	fmul dword [LightColor_G]
	fadd dword [GetSkyColor_G]
	fstp dword [GetSkyColor_G]

	fmul dword [LightColor_B]
	fadd dword [GetSkyColor_B]
	fstp dword [GetSkyColor_B]
	ret

;******************************************************************************
; Pick up a color that represents the sky from the `RayDir` vector.
;******************************************************************************
MapDist:
	push si
	fld dword [MapDist_Y]
	fstp dword [MapDist_Distance]
	mov word [MapDist_Index], -1
	mov cx, NumSpheres
	mov si, 0
.LoopForSpheres:
	mov ax, si
	mul word [SizeOf_Sphere]
	mov bx, ax
	fld dword [Spheres + bx + 0]
	fsub dword [MapDist_X]
	fmul st0
	fld dword [Spheres + bx + 4]
	fsub dword [MapDist_Y]
	fmul st0
	fadd
	fld dword [Spheres + bx + 8]
	fsub dword [MapDist_Z]
	fmul st0
	fadd
	fsqrt
	fsub dword [Spheres + bx + 12]
	fcom dword [MapDist_Distance]
	fstsw ax
	sahf
	jae .NextCompare
	fst dword [MapDist_Distance]
	mov [MapDist_Index], si
.NextCompare:
	fstp st0
	inc si
	loop .LoopForSpheres
	pop si
	ret

;******************************************************************************
; Calculate a ray from origin `RayOrg` and towards the direction `RayDir` that
; casts to the scene. Returns the cast point coordinates `MapCast` and the
; distance to the origin of the ray and the surface normal from the scene.
;******************************************************************************
MapCast:
	fldz
	fst dword [MapCast_D]
	fst dword [MapCast_NX]
	fst dword [MapCast_NY]
	fstp dword [MapCast_NZ]

; Stepping the point to go forward
	mov cx, MapCast_Iterate
.LoopIterate:
	fld dword [RayOrg_X]
	fld dword [RayDir_X]
	fmul dword [MapCast_D]
	fadd
	fstp dword [MapDist_X]

	fld dword [RayOrg_Y]
	fld dword [RayDir_Y]
	fmul dword [MapCast_D]
	fadd
	fstp dword [MapDist_Y]

	fld dword [RayOrg_Z]
	fld dword [RayDir_Z]
	fmul dword [MapCast_D]
	fadd
	fstp dword [MapDist_Z]

	call IsAwayFromBB
	jnc .InsideBB

	fld dword [RayDir_Y]
	fldz
	fcompp
	fstsw ax
	sahf
	jbe .ToSky
	
	; Hit the ground outside the bounding box
	fld1
	fstp dword [MapCast_NY]

	fld dword [RayOrg_Y]
	fldz
	fsub dword [RayDir_Y]
	fdiv
	fstp dword [MapCast_D]

	call .SetCastCrd

	mov word[MapCast_I], -1
	stc
	ret

; The origin of the ray is from outside of the bounding box and it's going to the sky
.ToSky:
	fld dword [MapDist_X]
	fstp dword [MapCast_X]
	fld dword [MapDist_Y]
	fstp dword [MapCast_Y]
	fld dword [MapDist_Z]
	fstp dword [MapCast_Z]
	mov word[MapCast_I], -2
	clc
	ret

; The origin of the ray is inside the bounding box
.InsideBB:
	push cx
	call MapDist
	pop cx

	fld dword [MapDist_Distance]
	fcomp dword [DistEpsilon]
	fstsw ax
	sahf
	ja .NotNearEnough

	mov ax, [MapDist_Index]
	mov [MapCast_I], ax
	cmp ax, 0
	jge .NotHitGround

	; Hit the ground inside the bounding box
	fld1
	fstp dword [MapCast_NY]

	fld dword [MapDist_X]
	fstp dword [MapCast_X]
	fld dword [MapDist_Y]
	fstp dword [MapCast_Y]
	fld dword [MapDist_Z]
	fstp dword [MapCast_Z]
	stc
	ret

; Should iterate again
.NotNearEnough:
	fld dword [MapCast_D]
	fadd dword [MapDist_Distance]
	fstp dword [MapCast_D]
	dec cx
	jcxz .ExitIterate
	jmp .LoopIterate

; Hit the spheres
.NotHitGround:
	mul word [SizeOf_Sphere]
	add ax, Spheres
	mov bx, ax

	; Calculate the normal
	fld dword [MapDist_X]
	fsub dword [bx + 0]
	fst dword [MapCast_NX]
	fmul st0
	fld dword [MapDist_Y]
	fsub dword [bx + 4]
	fst dword [MapCast_NY]
	fmul st0
	fadd
	fld dword [MapDist_Z]
	fsub dword [bx + 8]
	fst dword [MapCast_NZ]
	fmul st0
	fadd
	fsqrt ; Normalize the normal
	fld st0
	fld dword [MapCast_NX]
	fdivr
	fstp dword [MapCast_NX]
	fld st0
	fld dword [MapCast_NY]
	fdivr
	fstp dword [MapCast_NY]
	fdivr dword [MapCast_NZ]
	fstp dword [MapCast_NZ]

	; Set cast coord
	fld dword [MapDist_X]
	fstp dword [MapCast_X]
	fld dword [MapDist_Y]
	fstp dword [MapCast_Y]
	fld dword [MapDist_Z]
	fstp dword [MapCast_Z]
	stc
	ret

; Finished iteration
.ExitIterate:
	fld dword [MapDist_X]
	fstp dword [MapCast_X]
	fld dword [MapDist_Y]
	fstp dword [MapCast_Y]
	fld dword [MapDist_Z]
	fstp dword [MapCast_Z]
	mov word [MapCast_I], -2
	clc
	ret

; Subroutine: MapCast = RayOrg + RayDir * Dist
.SetCastCrd:
	fld dword [RayOrg_X]
	fld dword [RayDir_X]
	fmul dword [MapCast_D]
	fadd
	fstp dword [MapCast_X]

	fld dword [RayOrg_Y]
	fld dword [RayDir_Y]
	fmul dword [MapCast_D]
	fadd
	fstp dword [MapCast_Y]

	fld dword [RayOrg_Z]
	fld dword [RayDir_Z]
	fmul dword [MapCast_D]
	fadd
	fstp dword [MapCast_Z]
	ret

;******************************************************************************
; Check if the ray from the origin `RayOrg` towards the direction `RayDir` is
; going away from the bounding box
;******************************************************************************
IsAwayFromBB:
	fld dword [RayOrg_X]
	fcomp dword [BB_XNeg]
	fstsw ax
	sahf
jae .XNIsOK
	fld dword [RayDir_X]
	fcomp dword [FZero]
	fstsw ax
	sahf
jae .XNIsOK
	stc
	ret
.XNIsOK:

	fld dword [RayOrg_X]
	fcomp dword [BB_XPos]
	fstsw ax
	sahf
jbe .XPIsOK
	fld dword [RayDir_X]
	fcomp dword [FZero]
	fstsw ax
	sahf
jbe .XPIsOK
	stc
	ret
.XPIsOK:

	fld dword [RayOrg_Y]
	fcomp dword [BB_YNeg]
	fstsw ax
	sahf
jae .YNIsOK
	fld dword [RayDir_Y]
	fcomp dword [FZero]
	fstsw ax
	sahf
jae .YNIsOK
	stc
	ret
.YNIsOK:

	fld dword [RayOrg_Y]
	fcomp dword [BB_YPos]
	fstsw ax
	sahf
jbe .YPIsOK
	fld dword [RayDir_Y]
	fcomp dword [FZero]
	fstsw ax
	sahf
jbe .YPIsOK
	stc
	ret
.YPIsOK:

	fld dword [RayOrg_Z]
	fcomp dword [BB_ZNeg]
	fstsw ax
	sahf
jae .ZNIsOK
	fld dword [RayDir_Z]
	fcomp dword [FZero]
	fstsw ax
	sahf
jae .ZNIsOK
	stc
	ret
.ZNIsOK:

	fld dword [RayOrg_Z]
	fcomp dword [BB_ZPos]
	fstsw ax
	sahf
jbe .ZPIsOK
	fld dword [RayDir_Z]
	fcomp dword [FZero]
	fstsw ax
	sahf
jbe .ZPIsOK
	stc
	ret
.ZPIsOK:

	clc
	ret

;******************************************************************************
; Render the pixel by a given ray from the origin `RayOrg` towards the
; direction `RayDir`
;******************************************************************************
RenderScene:
	fld1
	fst dword [Mask_R]
	fst dword [Mask_G]
	fstp dword [Mask_B]
	fld dword [CamPos_X]
	fstp dword [RayOrg_X]
	fld dword [CamPos_Y]
	fstp dword [RayOrg_Y]
	fld dword [CamPos_Z]
	fstp dword [RayOrg_Z]

	mov cx, SampleDepth
.LoopSampling:
	push cx
	call MapCast
	pop cx
	jc .CastSphereOrGround

; If not cast then still step forward
.NotCast:
	fld dword [MapCast_X]
	fstp dword [RayOrg_X]
	fld dword [MapCast_Y]
	fstp dword [RayOrg_Y]
	fld dword [MapCast_Z]
	fstp dword [RayOrg_Z]

	dec cx
	jcxz .Finished1
	jmp .LoopSampling

.Finished1:
	jmp .Finished

; If cast to the spheres or the ground, do coloring
.CastSphereOrGround:
	mov ax, [MapCast_I]
	cmp ax, 0
	jl .CastGround

	; Casting spheres
	mul word [SizeOf_Sphere]
	mov bx, ax
	fld dword [Mask_R]
	fmul dword [Spheres + bx + 16]
	fstp dword [Mask_R]
	fld dword [Mask_G]
	fmul dword [Spheres + bx + 20]
	fstp dword [Mask_G]
	fld dword [Mask_B]
	fmul dword [Spheres + bx + 24]
	fstp dword [Mask_B]

	; Reflection
	fld dword [MapCast_NX]
	fmul dword [RayDir_X]
	fld dword [MapCast_NY]
	fmul dword [RayDir_Y]
	fadd
	fld dword [MapCast_NZ]
	fmul dword [RayDir_Z]
	fadd
	fadd st0 ; (Normal dot Ray) * 2
	
	fld st0
	fmul dword [MapCast_NX]
	fsubr dword [RayDir_X]
	fstp dword [RayDir_X]
	
	fld st0
	fmul dword [MapCast_NY]
	fsubr dword [RayDir_Y]
	fstp dword [RayDir_Y]

	fmul dword [MapCast_NZ]
	fsubr dword [RayDir_Z]
	fstp dword [RayDir_Z]

	call .SetRayOrg

	dec cx
	jcxz .Finished
	jmp .LoopSampling

; The ray is casting the ground
.CastGround:
	fld dword [MapCast_X]
	fadd st0
	fistp word [TempW]
	fwait
	mov ax, [TempW]
	fld dword [MapCast_Z]
	fadd st0
	fistp word [TempW]
	fwait
	xor ax, [TempW]
	test ax, 1
	jz .GroundColorPattern

	fld dword [Mask_R]
	fmul dword [F05]
	fstp dword [Mask_R]
	fld dword [Mask_G]
	fmul dword [F05]
	fstp dword [Mask_G]
	fld dword [Mask_B]
	fmul dword [F05]
	fstp dword [Mask_B]

.GroundColorPattern:
	fld dword [RayDir_Y]
	fabs
	fstp dword [RayDir_Y]

	call .SetRayOrg

	dec cx
	jcxz .Finished
	jmp .LoopSampling

; Finished iteration
.Finished:
	call GetSkyColor
	fld dword [GetSkyColor_R]
	fmul dword [Mask_R]
	fimul word [C255]
	fistp word [Pixel_R]
	fld dword [GetSkyColor_G]
	fmul dword [Mask_G]
	fimul word [C255]
	fistp word [Pixel_G]
	fld dword [GetSkyColor_B]
	fmul dword [Mask_B]
	fimul word [C255]
	fistp word [Pixel_B]
	fwait

; Clamp the color not to overflow
	cmp word [Pixel_R], 255
	jle .R_OK
	mov word [Pixel_R], 255
.R_OK:
	cmp word [Pixel_G], 255
	jle .G_OK
	mov word [Pixel_G], 255
.G_OK:
	cmp word [Pixel_B], 255
	jle .B_OK
	mov word [Pixel_B], 255
.B_OK:

	call PickColor
	ret

; When cast, set the ray origin near the cast point
.SetRayOrg:
	fld dword [MapCast_X]
	fld dword [RayDir_X]
	fmul dword [DistEpsilon2]
	fadd
	fstp dword [RayOrg_X]
	
	fld dword [MapCast_Y]
	fld dword [RayDir_Y]
	fmul dword [DistEpsilon2]
	fadd
	fstp dword [RayOrg_Y]

	fld dword [MapCast_Z]
	fld dword [RayDir_Z]
	fmul dword [DistEpsilon2]
	fadd
	fstp dword [RayOrg_Z]
	ret

Segment .data
X_Res dw 320
Y_Res dw 200

SavedVideoMode dw 0
F65536 dd 65536.0
F30625 dd 3.0625
FM175 dd -1.75
FTimeFreq dd 1193186.0
FBigValue dd 9999999.0
FZero dd 0
F05 dd 0.5
C2 dw 2
C255 dw 255
C256 dw 256
C1000 dw 1000

DitherMatrix:
	%assign dm_y 0
	%rep 16
		%assign dm_x 0
		%rep 16
			%assign xor_val dm_x ^ dm_y
			%assign dm_val          (((xor_val & 0x01) >> 0) << 7) | (((dm_y & 0x01) >> 0) << 6)
			%assign dm_val dm_val | (((xor_val & 0x02) >> 1) << 5) | (((dm_y & 0x02) >> 1) << 4)
			%assign dm_val dm_val | (((xor_val & 0x04) >> 2) << 3) | (((dm_y & 0x04) >> 2) << 2)
			%assign dm_val dm_val | (((xor_val & 0x08) >> 3) >> 1) | (((dm_y & 0x08) >> 3) >> 0)
			db dm_val
			%assign dm_x dm_x + 1
		%endrep
		%assign dm_y dm_y + 1
	%endrep

TempW dw 0

Pixel_X dw 0
Pixel_Y dw 0
Pixel_R dw 0
Pixel_G dw 0
Pixel_B dw 0

MapDist_X dd 0
MapDist_Y dd 0
MapDist_Z dd 0
MapDist_Distance dd 0
MapDist_Index dw 0

RayDir_X dd 0
RayDir_Y dd 0
RayDir_Z dd 0

RayOrg_X dd 0
RayOrg_Y dd 0
RayOrg_Z dd 0

RayDist dd 0
DistEpsilon dd 0.01
DistEpsilon2 dd 0.02

MapCast_X dd 0
MapCast_Y dd 0
MapCast_Z dd 0
MapCast_NX dd 0
MapCast_NY dd 0
MapCast_NZ dd 0
MapCast_D dd 0
MapCast_I dw 0

Mask_R dd 0
Mask_G dd 0
Mask_B dd 0

GetSkyColor_R dd 0
GetSkyColor_G dd 0
GetSkyColor_B dd 0
