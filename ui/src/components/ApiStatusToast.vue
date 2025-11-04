<template>
  <div class="flex flex-col gap-2">
    <PHeading :heading="6">
      {{ isAuth ? 'Access denied.' : 'Oops. Something went wrong.' }}
    </PHeading>
    <template v-if="isAuth">
      <div>
        You are not authorized. Please sign in or check permissions.
      </div>
    </template>
    <template v-else>
      <template v-if="showPromotionalContent">
        <div>
          You can use Prefect Cloud for free, anytime.
        </div>
        <div>
          <PButton to="https://app.prefect.cloud/auth/sign-up?utm_source=prefect-oss&utm_medium=toast" variant="default" target="_blank">
            Try it now
          </PButton>
        </div>
      </template>
      <template v-else>
        <div>
          Please check your connection and try again.
        </div>
      </template>
    </template>
  </div>
</template>

<script lang="ts" setup>
  import { PButton, PHeading } from '@prefecthq/prefect-design'
  import { computed } from 'vue'

  const props = defineProps<{ kind?: 'auth' | 'other' }>()
  const isAuth = computed(() => (props.kind ?? 'other') === 'auth')

  // Read from localStorage, default to true
  const cachedSetting = localStorage.getItem('prefect-show-promotional-content')
  const showPromotionalContent = computed(() => cachedSetting !== 'false')
</script>