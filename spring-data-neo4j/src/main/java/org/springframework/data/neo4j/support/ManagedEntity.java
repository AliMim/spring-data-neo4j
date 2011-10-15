/**
 * Copyright 2011 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.springframework.data.neo4j.support;

import org.springframework.data.neo4j.core.EntityState;

/**
 * @author mh
 * @since 02.10.11
 */
public interface ManagedEntity<S> {
    /**
     * Attach the entity inside a running transaction. Creating or changing an entity outside of a transaction
     * detaches it. It must be subsequently attached in order to be persisted.
     *
     * @return the attached entity
     */
    <T> T persist();

    S getPersistentState();

    EntityState<S> getEntityState();

    void setPersistentState(S state);

    boolean hasPersistentState();
}
