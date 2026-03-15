-- 422. «Клієнт з ефектом звуження вибору»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
FROM level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,order_id
	   ,COUNT(distinct product_id) as count_unik_prod
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id),
level4 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn_first_3
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_last_3
FROM level2
JOIN level3 USING (customer_id, order_id)),
level5 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE rn_first_3 <= 3)::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE rn_last_3 <= 3)::numeric,2) as avg_chek_last
	   ,ROUND(AVG(count_unik_prod) FILTER (WHERE rn_first_3 <= 3)::numeric,2) as avg_count_first
	   ,ROUND(AVG(count_unik_prod) FILTER (WHERE rn_last_3 <= 3)::numeric,2) as avg_count_last
FROM level4
GROUP BY customer_id)
SELECT *
FROM level5
WHERE avg_count_first > avg_count_last AND avg_chek_last >= avg_chek_first

-- 423. «Клієнт з ефектом запізнілого прискорення»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROM level1
WHERE count_order >= 8),
level3 as(SELECT *
       ,ROUND((sum_chek / prev_chek)::numeric,2) as diff_delta
	   ,NTILE(3) OVER (partition by customer_id order by order_date) as ntile_3
FROM level2),
level4 as(SELECT customer_id
       ,ntile_3
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek_per_ntile
FROM level3
GROUP BY customer_id, ntile_3),
level5 as(SELECT *
FROM level3
JOIN level4 USING (customer_id, ntile_3)),
level6 as(SELECT *
       ,ROUND(AVG(diff_delta) FILTER (WHERE ntile_3 = 1) OVER (partition by customer_id)::numeric,2) as avg_delta_ntile_1
	   ,ROUND(AVG(diff_delta) FILTER (WHERE ntile_3 = 2) OVER (partition by customer_id)::numeric,2) as avg_delta_ntile_2
	   ,ROUND(AVG(diff_delta) FILTER (WHERE ntile_3 = 3) OVER (partition by customer_id)::numeric,2) as avg_delta_ntile_3
FROM level5),
level7 as(SELECT DISTINCT customer_id, ntile_3, count_order
       ,median_chek_per_ntile
	   ,avg_delta_ntile_1
	   ,avg_delta_ntile_2
	   ,avg_delta_ntile_3
FROM level6),
level8 as(SELECT *
       ,case when avg_delta_ntile_1 <= 1.05 AND avg_delta_ntile_2 <= 1.1 AND avg_delta_ntile_3 >= 1.3 THEN 'yes'
	   ELSE 'no' END as gradation
FROM level7)
SELECT *
FROM level8
WHERE gradation = 'yes'

-- 424. «Клієнт з ефектом зламаної інерції»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek 
FROM level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,sum_chek - prev_chek as delta
FROM level2),
level4 as(SELECT customer_id
       ,ROUND(percentile_cont(0.5) WITHIN GROUP (order by delta)::numeric,2) as median_delta
FROM level3
GROUP By customer_id),
level5 as(SELECT *
       ,ABS(delta - median_delta) as abs_diff_delta
FROM level3
JOIN level4 USING (customer_id)
WHERE prev_chek is not null),
level6 as(SELECT *
       ,MAX(abs_diff_delta) OVER (partition by customer_id) as max_abs_diff_delta
FROM level5),
level7 as(SELECT *
       ,MAX(case when abs_diff_delta = max_abs_diff_delta THEN order_date END) OVER (partition by customer_id) as date_in_max_abs_delta
FROM level6),
level8 as(SELECT *
       ,case when order_date < date_in_max_abs_delta THEN '1_before'
	   when order_date = date_in_max_abs_delta THEN 'break'
	   when order_date > date_in_max_abs_delta THEN '2_after'
	   END as groups
FROM level7),
level9 as(SELECT *
FROM level8
WHERE groups IN ('1_before','2_after')),
level10 as(SELECT customer_id
       ,ROUND(STDDEV(abs_diff_delta) FILTER (WHERE groups = '1_before')::numeric,2) as std_dev_delta_before
	   ,ROUND(STDDEV(abs_diff_delta) FILTER (WHERE groups = '2_after')::numeric,2) as std_dev_delta_after
FROM level9
GROUP By customer_id),
level11 as(SELECT *
FROm level10
WHERE std_dev_delta_before is not null AND std_dev_delta_after is not null)
SELECT *
FROM level11
WHERE std_dev_delta_after >= 2 * std_dev_delta_before

-- 425. «Клієнт з ефектом перекосу ритму»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,order_date - prev_date as interval
FROM level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn_first
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_last
FROm level2
WHERE interval is not null),
level4 as(SELECT customer_id
       ,ROUND(STDDEV(interval) FILTER (WHERE rn_first <= 3)::numeric,2) as std_dev_interval_first
	   ,ROUND(STDDEV(interval) FILTER (WHERE rn_last <= 3)::numeric,2) as std_dev_interval_last
	   ,ROUND(AVG(interval) FILTER (WHERE rn_first <= 3)::numeric,2) as avg_interval_first
	   ,ROUND(AVG(interval) FILTER (WHERE rn_last <= 3)::numeric,2) as avg_interval_last
FROM level3
GROUP By customer_id)
SELECT *
FROM level4
WHERE std_dev_interval_last >= 2 * std_dev_interval_first AND avg_interval_last <= avg_interval_first

-- 426. «Клієнт з ефектом втраченої точки»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIn order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROM level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,ROUND((sum_chek / prev_chek)::numeric,2) as ratio
FROM level2),
level4 as(SELECT *
       ,MAX(ratio) OVER (partition by customer_id) as max_ratio
FROm level3),
level5 as(SELECT *
       ,MAX(case when ratio = max_ratio THEN order_date END) OVER (partition by customer_id) as date_max_ratio
FROm level4
WHERE prev_chek is not null),
level6 as(SELECT *
       ,case when order_date < date_max_ratio THEN '1_before'
	   when order_date = date_max_ratio THEN 'break'
	   when order_date > date_max_ratio THEN '2_after'
	   END as groups
FROm level5),
level7 as(SELECT customer_id
       ,ROUND(AVG(ratio) FILTER (WHERE groups = '1_before')::numeric,2) as avg_ratio_before
	   ,ROUND(AVG(ratio) FILTER (WHERE groups = '2_after')::numeric,2) as avg_ratio_after
FROM level6
WHERE groups IN ('1_before','2_after')
GROUP BY customer_id),
level8 as(SELECT *
FROM level7
WHERE avg_ratio_before is not null AND avg_ratio_after is not null),
level9 as(SELECT *
       ,case when avg_ratio_before >= 1.05 AND avg_ratio_after <= 0.98 THEN 'yes'
	   ELSE 'no' END as gradation
FROM level8)
SELECT *
FROM level9
WHERE gradation = 'yes'

-- 427. «Клієнт з ефектом наздоганяння»

WITH order_level AS (
    SELECT
        o.customer_id,
        o.order_id,
        o.order_date,
        SUM(od.unit_price * od.quantity * (1 - od.discount)) AS order_amount,
        COUNT(*) OVER (PARTITION BY o.customer_id) AS cnt_orders
    FROM orders o
    JOIN order_details od USING (order_id)
    GROUP BY o.customer_id, o.order_id, o.order_date
),
base AS (
    SELECT
        *,
        MAX(order_amount) OVER (
            PARTITION BY customer_id
            ORDER BY order_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS historical_max
    FROM order_level
    WHERE cnt_orders >= 7
),
below_max AS (
    SELECT
        *,
        CASE WHEN order_amount < historical_max THEN 1 ELSE 0 END AS is_below_max
    FROM base
),
gap_count AS (
    SELECT
        *,
        SUM(is_below_max) OVER (
            PARTITION BY customer_id
            ORDER BY order_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS below_counter
    FROM below_max
),
catchup_point AS (
    SELECT
        *
    FROM gap_count
    WHERE
        order_amount >= historical_max
        AND below_counter >= 2
),
first_catchup AS (
    SELECT DISTINCT ON (customer_id)
        customer_id,
        order_id AS catchup_order_id,
        order_date
    FROM catchup_point
    ORDER BY customer_id, order_date
),
joined AS (
    SELECT
        b.customer_id,
        b.order_amount,
        f.catchup_order_id,
        f.order_date AS catchup_date,
        CASE
            WHEN b.order_date < f.order_date THEN 'during_drop'
            WHEN b.order_date > f.order_date THEN 'after_catchup'
        END AS period
    FROM base b
    JOIN first_catchup f USING (customer_id)
),
final AS (
    SELECT
        customer_id,
        catchup_order_id,
        AVG(order_amount) FILTER (WHERE period = 'during_drop') AS avg_amount_during_drop,
        AVG(order_amount) FILTER (WHERE period = 'after_catchup') AS avg_amount_after_catchup
    FROM joined
    GROUP BY customer_id, catchup_order_id
)
SELECT *
FROM final
WHERE avg_amount_after_catchup > avg_amount_during_drop;

