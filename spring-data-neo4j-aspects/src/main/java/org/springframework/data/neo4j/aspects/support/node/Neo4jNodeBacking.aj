/*
 * Copyright 2010 the original author or authors.
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

package org.springframework.data.neo4j.aspects.support.node;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.aspectj.lang.JoinPoint;
import org.aspectj.lang.reflect.FieldSignature;
import org.neo4j.graphdb.DynamicRelationshipType;
import org.neo4j.graphdb.Path;
import org.neo4j.graphdb.Node;
import org.neo4j.graphdb.Relationship;
import org.neo4j.graphdb.traversal.TraversalDescription;
import org.neo4j.graphdb.traversal.Traverser;

import org.springframework.data.neo4j.annotation.NodeEntity;
import org.springframework.data.neo4j.annotation.RelationshipEntity;
import org.springframework.data.neo4j.annotation.RelatedTo;
import org.springframework.data.neo4j.annotation.GraphProperty;
import org.springframework.data.neo4j.annotation.GraphId;
import org.springframework.data.neo4j.annotation.Query;
import org.springframework.data.neo4j.annotation.RelatedToVia;
import org.springframework.data.neo4j.annotation.GraphTraversal;

import org.springframework.data.neo4j.aspects.core.NodeBacked;
import org.springframework.data.neo4j.aspects.core.RelationshipBacked;
import org.springframework.data.neo4j.support.EntityStateHandler;
import org.springframework.data.neo4j.support.RelationshipResult;
import org.springframework.data.neo4j.support.node.NodeEntityStateFactory;
import org.springframework.data.neo4j.support.DoReturn;
import org.springframework.data.neo4j.core.EntityPath;
import org.springframework.data.neo4j.core.EntityState;
import org.springframework.data.neo4j.support.GraphDatabaseContext;

import org.springframework.data.neo4j.support.path.EntityPathPathIterableWrapper;
import org.springframework.data.neo4j.support.query.CypherQueryExecutor;
import org.springframework.data.neo4j.aspects.support.relationship.ManagedRelationshipEntity;
import javax.persistence.Transient;
import javax.persistence.Entity;

import java.lang.reflect.Field;
import java.util.Map;

import static org.springframework.data.neo4j.support.DoReturn.unwrap;

/**
 * Aspect for handling node entity creation and field access (read & write)
 * puts the underlying state (Node) into and delegates field access to an {@link org.springframework.data.neo4j.core.EntityState} instance,
 * created by a configured {@link NodeEntityStateFactory}.
 *
 * Handles constructor invocation and partial entities as well.
 */
public privileged aspect Neo4jNodeBacking {

    protected final Log log = LogFactory.getLog(getClass());

    declare parents : (@NodeEntity *) implements ManagedNodeEntity;

    private GraphDatabaseContext graphDatabaseContext;
    private NodeEntityStateFactory entityStateFactory;

    /**
     * State accessors that encapsulate the underlying state and the behaviour related to it (field access, creation)
     */
    private transient EntityState<Node> ManagedNodeEntity.entityState;


    public void setGraphDatabaseContext(GraphDatabaseContext graphDatabaseContext) {
        this.graphDatabaseContext = graphDatabaseContext;
    }
    public void setNodeEntityStateFactory(NodeEntityStateFactory entityStateFactory) {
        this.entityStateFactory = entityStateFactory;
    }

    declare @field: @GraphProperty * (@Entity @NodeEntity(partial=true) *).*:@Transient;
    declare @field: @RelatedTo * (@Entity @NodeEntity(partial=true) *).*:@Transient;
    declare @field: @RelatedToVia * (@Entity @NodeEntity(partial=true) *).*:@Transient;
    declare @field: @GraphId * (@Entity @NodeEntity(partial=true) *).*:@Transient;
    declare @field: @GraphTraversal * (@Entity @NodeEntity(partial=true) *).*:@Transient;
    declare @field: @Query * (@Entity @NodeEntity(partial=true) *).*:@Transient;



    protected pointcut entityFieldGet(ManagedNodeEntity entity) :
            get(* ManagedNodeEntity+.*) &&
            this(entity) &&
            !get(* ManagedNodeEntity.*);


    protected pointcut entityFieldSet(ManagedNodeEntity entity, Object newVal) :
            set(* ManagedNodeEntity+.*) &&
            this(entity) &&
            args(newVal) &&
            !set(* ManagedNodeEntity.*);


    /**
     * pointcut for constructors not taking a node to be handled by the aspect and the {@link org.springframework.data.neo4j.core.EntityState}
     */
	pointcut arbitraryUserConstructorOfNodeBackedObject(ManagedNodeEntity entity) :
		execution((@NodeEntity *).new(..)) &&
		!execution((@NodeEntity *).new(Node)) &&
		this(entity) && !cflowbelow(call(* fromStateInternal(..)));


    /**
     * Handle outside entity instantiation by either creating an appropriate backing node in the graph or in the case
     * of a reinstantiated partial entity by assigning the original node to the entity, the concrete behaviour is delegated
     * to the {@link org.springframework.data.neo4j.core.EntityState}. Also handles the java type representation in the graph.
     * When running outside of a transaction, no node is created, this is handled later when the entity is accessed within
     * a transaction again.
     */
    before(ManagedNodeEntity entity): arbitraryUserConstructorOfNodeBackedObject(entity) {
        if (entityStateFactory == null) {
            log.error("entityStateFactory not set, not creating accessors for " + entity.getClass());
        } else {
            if (entity.entityState != null) return;
            entity.entityState = entityStateFactory.getEntityState(entity, true);
        }
    }


    public <T> T ManagedNodeEntity.persist() {
        return (T)this.entityState.persist();
    }

	public void ManagedNodeEntity.setPersistentState(Node n) {
        if (this.entityState == null) {
            this.entityState = Neo4jNodeBacking.aspectOf().entityStateFactory.getEntityState(this, false);
        }
        this.entityState.setPersistentState(n);
	}

	public Node ManagedNodeEntity.getPersistentState() {
		return this.entityState!=null ? this.entityState.getPersistentState() : null;
	}
	
    public EntityState<Node> ManagedNodeEntity.getEntityState() {
        return entityState;
    }

    public boolean ManagedNodeEntity.hasPersistentState() {
        return this.entityState!=null && this.entityState.hasPersistentState();
    }


    public static GraphDatabaseContext graphDatabaseContext() {
        return Neo4jNodeBacking.aspectOf().graphDatabaseContext;
    }

    /**
     * @param obj
     * @return result of equals operation fo the underlying node, false if there is none
     */
	public boolean ManagedNodeEntity.equals(Object obj) {
        return entityStateHandler().equals(this, obj);
	}

    public static EntityStateHandler entityStateHandler() {
        return graphDatabaseContext().getEntityStateHandler();
    }

    /**
     * @return result of the hashCode of the underlying node (if any, otherwise identityHashCode)
     */
	public int ManagedNodeEntity.hashCode() {
        return entityStateHandler().hashCode(this);
	}

    /**
     * delegates field reads to the state accessors instance
     */
    Object around(ManagedNodeEntity entity): entityFieldGet(entity) {
        if (entity.entityState==null) return proceed(entity);
        Object result=entity.entityState.getValue(field(thisJoinPoint));
        if (result instanceof DoReturn) return unwrap(result);
        return proceed(entity);
    }

    /**
     * delegates field writes to the state accessors instance
     */
    Object around(ManagedNodeEntity entity, Object newVal) : entityFieldSet(entity, newVal) {
        if (entity.entityState==null) return proceed(entity,newVal);
        Object result=entity.entityState.setValue(field(thisJoinPoint),newVal);
        if (result instanceof DoReturn) return unwrap(result);
        return proceed(entity,result);
	}

    Field field(JoinPoint joinPoint) {
        FieldSignature fieldSignature = (FieldSignature)joinPoint.getSignature();
        return fieldSignature.getField();
    }

}
