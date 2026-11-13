package nerarth.mods.honeycombplus.mixin;

import nerarth.mods.honeycombplus.HoneycombPlus;
import nerarth.mods.honeycombplus.item.ModItems;
import net.minecraft.advancements.triggers.InventoryChangeTrigger;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.Identifier;
import net.minecraft.resources.ResourceKey;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.stats.ServerRecipeBook;
import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.item.crafting.Ingredient;
import net.minecraft.world.item.crafting.Recipe;
import net.minecraft.world.item.crafting.RecipeHolder;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

import java.util.ArrayList;
import java.util.List;

@Mixin(InventoryChangeTrigger.class)
public class InventoryChangeTriggerMixin {

	@Unique
	private static final ResourceKey<Recipe<?>> WAX_SMELTING_RECIPE = ResourceKey.create(
		Registries.RECIPE,
		Identifier.fromNamespaceAndPath(HoneycombPlus.MOD_ID, "wax")
	);

	@Inject(
		method = "trigger(Lnet/minecraft/server/level/ServerPlayer;Lnet/minecraft/world/entity/player/Inventory;Lnet/minecraft/world/item/ItemStack;)V",
		at = @At("TAIL")
	)
	private void honeycombplus$autoDiscoverRecipes(ServerPlayer player, Inventory inventory, ItemStack stack, CallbackInfo ci) {
		if (stack.isEmpty()) {
			return;
		}

		boolean thematicItem = honeycombplus$isThematicIngredient(stack);
		boolean isWaxItem = stack.is(ModItems.WAX);
		ServerRecipeBook recipeBook = player.getRecipeBook();

		// For non-thematic items (e.g. unwaxed copper blocks), only evaluate copper waxing recipes
		// if the player already knows or possesses Fine Wax.
		boolean hasWaxKnowledge = isWaxItem
			|| recipeBook.contains(WAX_SMELTING_RECIPE)
			|| inventory.contains(invStack -> invStack.is(ModItems.WAX));

		if (!thematicItem && !hasWaxKnowledge) {
			return;
		}

		List<RecipeHolder<?>> toUnlock = new ArrayList<>();

		for (RecipeHolder<?> holder : player.level().recipeAccess().getRecipes()) {
			Identifier id = holder.id().identifier();
			if (!HoneycombPlus.MOD_ID.equals(id.getNamespace())) {
				continue;
			}
			if (recipeBook.contains(holder.id())) {
				continue;
			}

			String path = id.getPath();
			boolean isCopperWaxingRecipe = path.startsWith("waxed_") && path.endsWith("_from_wax");
			List<Ingredient> ingredients = holder.value().placementInfo().ingredients();

			if (!isCopperWaxingRecipe) {
				if (thematicItem && honeycombplus$matchesAnyIngredient(ingredients, stack)) {
					toUnlock.add(holder);
				}
			} else {
				if (isWaxItem) {
					// Player just acquired Fine Wax: unlock waxed_<block>_from_wax for any unwaxed copper blocks currently in inventory
					if (honeycombplus$inventoryHasOtherIngredient(ingredients, stack, inventory)) {
						toUnlock.add(holder);
					}
				} else if (hasWaxKnowledge && !thematicItem) {
					// Player acquired an unwaxed copper block and already has/knows Fine Wax
					if (honeycombplus$matchesAnyIngredient(ingredients, stack)) {
						toUnlock.add(holder);
					}
				}
			}
		}

		if (!toUnlock.isEmpty()) {
			player.awardRecipes(toUnlock);
		}
	}

	@Unique
	private static boolean honeycombplus$isThematicIngredient(ItemStack stack) {
		if (stack.is(Items.HONEYCOMB) || stack.is(Items.HONEYCOMB_BLOCK) || stack.is(Items.HONEY_BOTTLE)) {
			return true;
		}
		Identifier itemId = BuiltInRegistries.ITEM.getKey(stack.getItem());
		return HoneycombPlus.MOD_ID.equals(itemId.getNamespace());
	}

	@Unique
	private static boolean honeycombplus$matchesAnyIngredient(List<Ingredient> ingredients, ItemStack stack) {
		for (Ingredient ingredient : ingredients) {
			if (ingredient.test(stack)) {
				return true;
			}
		}
		return false;
	}

	@Unique
	private static boolean honeycombplus$inventoryHasOtherIngredient(List<Ingredient> ingredients, ItemStack waxStack, Inventory inventory) {
		for (Ingredient ingredient : ingredients) {
			if (!ingredient.test(waxStack)) {
				if (inventory.contains(invStack -> !invStack.isEmpty() && ingredient.test(invStack))) {
					return true;
				}
			}
		}
		return false;
	}
}
