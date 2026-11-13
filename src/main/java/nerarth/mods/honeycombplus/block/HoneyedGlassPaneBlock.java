package nerarth.mods.honeycombplus.block;

import net.minecraft.core.BlockPos;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.InsideBlockEffectApplier;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.item.PrimedTnt;
import net.minecraft.world.entity.vehicle.boat.AbstractBoat;
import net.minecraft.world.entity.vehicle.minecart.AbstractMinecart;
import net.minecraft.world.item.DyeColor;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.SoundType;
import net.minecraft.world.level.block.StainedGlassPaneBlock;
import net.minecraft.world.level.block.state.BlockBehaviour;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.Vec3;

public class HoneyedGlassPaneBlock extends StainedGlassPaneBlock {
    private static final double SLIDE_STARTS_WHEN_VERTICAL_SPEED_IS_AT_LEAST = 0.13D;
    private static final double MIN_FALL_SPEED_TO_BE_CONSIDERED_SLIDING = 0.08D;
    private static final double THROTTLE_SLIDE_SPEED_TO = 0.05D;

    public HoneyedGlassPaneBlock(BlockBehaviour.Properties properties) {
        super(DyeColor.ORANGE, properties);
    }

    @Override
    public void fallOn(Level level, BlockState state, BlockPos pos, Entity entity, double fallDistance) {
        entity.playSound(SoundEvents.HONEY_BLOCK_SLIDE, 1.0F, 1.0F);
        if (!level.isClientSide()) {
            level.broadcastEntityEvent(entity, (byte) 54);
        }
        if (entity.causeFallDamage(fallDistance, 0.2F, level.damageSources().fall())) {
            SoundType soundType = this.soundType;
            entity.playSound(soundType.getFallSound(), soundType.getVolume() * 0.5F, soundType.getPitch() * 0.75F);
        }
    }

    @Override
    protected void entityInside(BlockState state, Level level, BlockPos pos, Entity entity, InsideBlockEffectApplier effectApplier, boolean isPrecise) {
        Vec3 delta = entity.getDeltaMovement();
        // Apply sticky horizontal drag when brushing against or moving through the pane
        double newX = delta.x * 0.7D;
        double newZ = delta.z * 0.7D;
        double newY = delta.y;

        if (isSlidingDown(pos, entity)) {
            double oldDeltaY = getOldDeltaY(delta.y);
            if (oldDeltaY < -SLIDE_STARTS_WHEN_VERTICAL_SPEED_IS_AT_LEAST) {
                double factor = -THROTTLE_SLIDE_SPEED_TO / oldDeltaY;
                newX = delta.x * factor;
                newZ = delta.z * factor;
                newY = getNewDeltaY(-THROTTLE_SLIDE_SPEED_TO);
            } else {
                newY = getNewDeltaY(-THROTTLE_SLIDE_SPEED_TO);
            }
            entity.resetFallDistance();
            maybeDoSlideEffects(level, entity);
        }

        entity.setDeltaMovement(new Vec3(newX, newY, newZ));
        super.entityInside(state, level, pos, entity, effectApplier, isPrecise);
    }

    private static double getOldDeltaY(double deltaY) {
        return deltaY / 0.98F + 0.08D;
    }

    private static double getNewDeltaY(double deltaY) {
        return (deltaY - 0.08D) * 0.98F;
    }

    private boolean isSlidingDown(BlockPos pos, Entity entity) {
        if (entity.onGround()) {
            return false;
        }
        if (entity.getY() > (double) pos.getY() + 0.9375D - 1.0E-7D) {
            return false;
        }
        if (getOldDeltaY(entity.getDeltaMovement().y) >= -MIN_FALL_SPEED_TO_BE_CONSIDERED_SLIDING) {
            return false;
        }
        return true;
    }

    private static boolean doesEntityDoHoneyBlockSlideEffects(Entity entity) {
        return entity instanceof LivingEntity || entity instanceof AbstractMinecart || entity instanceof PrimedTnt || entity instanceof AbstractBoat;
    }

    private void maybeDoSlideEffects(Level level, Entity entity) {
        if (doesEntityDoHoneyBlockSlideEffects(entity)) {
            if (level.getRandom().nextInt(5) == 0) {
                entity.playSound(SoundEvents.HONEY_BLOCK_SLIDE, 1.0F, 1.0F);
            }
            if (!level.isClientSide() && level.getRandom().nextInt(5) == 0) {
                level.broadcastEntityEvent(entity, (byte) 53);
            }
        }
    }
}
